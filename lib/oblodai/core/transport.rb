# frozen_string_literal: true

require_relative "clock"
require_relative "envelope"
require_relative "http"
require_relative "idempotency"
require_relative "logger"
require_relative "request"
require_relative "retry"
require_relative "signing"
require_relative "util"
require_relative "../errors"

module Oblodai
  # The HTTP engine every resource goes through. One method, {#call}, does the whole lifecycle:
  # serialize → sign → send (with timeout) → decode envelope → classify error → retry per policy.
  # {#call_raw} serves the few `bare` routes that return bytes instead of JSON (PDF documents).
  class Transport
    # Error codes that mean the core rejected the signature because of the timestamp or MAC.
    SIGNATURE_FAILURE_CODES = ["merchant.bad_signature", "auth.bad_timestamp"].freeze

    # Response body caps. The SDK buffers the whole body, so an endless or mistargeted stream would
    # otherwise grow until the process dies. JSON envelopes are small (the largest recorded fixture
    # is a few hundred kB); `bare` routes are PDFs and CSV statements.
    MAX_JSON_BODY_BYTES = 8 * 1024 * 1024
    MAX_BARE_BODY_BYTES = 64 * 1024 * 1024

    # @return [String]
    attr_reader :base_url

    # @param base_url [String]
    # @param user_agent [String]
    # @param credentials [Oblodai::RequestBuilder::Credentials, nil] the merchant's one API key;
    #   it signs every route the core gates with `key`
    # @param http [#call] HTTP adapter
    # @param timeout_ms [Integer] per-attempt timeout
    # @param deadline_ms [Integer] overall budget per call, including retries and pauses
    # @param retry_policy [Oblodai::RetryPolicy]
    # @param clock [Oblodai::Clock]
    # @param logger [#debug]
    # @param headers [Hash] extra headers on every request
    # @param admin_token [String, nil] sent as X-Admin-Token on `onboard` routes only
    def initialize(base_url:, user_agent:, credentials: nil, http: nil, timeout_ms: 30_000,
                   deadline_ms: 90_000, retry_policy: RetryPolicy.new, clock: Clock.new,
                   logger: NullLogger.new, headers: {}, admin_token: nil)
      @base_url = base_url
      @user_agent = user_agent
      @credentials = credentials
      @http = http || HTTP::NetHTTPAdapter.new
      @timeout_ms = timeout_ms
      @deadline_ms = deadline_ms
      @retry = retry_policy
      @clock = clock
      # Wrapped, not trusted: whatever logger the caller injected receives fields that were redacted
      # before it saw them, so a pino-style sink cannot be the thing that prints a signing secret.
      @logger = Logging.redacting(logger)
      @headers = headers || {}
      @admin_token = admin_token
    end

    # What this transport is pointed at — never how it proves who it is.
    def inspect
      "#<Oblodai::Transport base_url=#{@base_url.inspect} " \
        "credentials=#{describe_credentials(@credentials)} " \
        "admin_token=#{@admin_token ? "[redacted]" : "none"}>"
    end
    alias to_s inspect

    # Call an envelope route and return its `result`.
    #
    # @param route [Oblodai::Contract::Route]
    # @return [Object] the decoded `result`
    # @raise [Oblodai::Error]
    def call(route, body: nil, query: nil, path_params: nil, idempotency_key: nil,
             timeout_ms: nil, deadline_ms: nil)
      raw = execute(route, body: body, query: query, path_params: path_params,
                           idempotency_key: idempotency_key, timeout_ms: timeout_ms,
                           deadline_ms: deadline_ms)
      decoded = Envelope.decode(raw.status, raw.body)
      result = decoded.result
      # The core replays a cached response by Idempotency-Key; when the original was too large to
      # cache it answers {ok, idempotent_replay: true, detail} instead of the object — surface that.
      if result.is_a?(Hash) && result["idempotent_replay"] == true
        raise ContractError.new(
          "#{route.key}: the request was already processed but its response was too large to " \
          "replay — fetch the result by order_id/reference (#{result["detail"]})",
          raw.status, result
        )
      end
      result
    end

    # Call a `bare` route and return the raw response (status already checked to be 2xx).
    # @return [Oblodai::HTTP::Response]
    def call_raw(route, **options)
      execute(route, **options)
    end

    private

    def execute(route, body: nil, query: nil, path_params: nil, idempotency_key: nil,
                timeout_ms: nil, deadline_ms: nil)
      payload = RequestBuilder.serialize_body(body, route.method)
      key = resolve_idempotency_key(route, idempotency_key)
      safe_to_repeat = route.safe || (route.idempotent && !key.nil?)
      deadline = Util.monotonic_ms + (deadline_ms || @deadline_ms)
      max_bytes = route.bare ? MAX_BARE_BODY_BYTES : MAX_JSON_BODY_BYTES
      attempt = 0
      skew = { tried: false, before: 0, installed: 0 }

      loop do
        # The offset this attempt is signed with. Compared against the server's own time below —
        # never against the shared offset, which a concurrent call may already have corrected.
        signed_offset = @clock.offset
        request = build_request(route, payload, key, path_params, query)
        @logger.debug("request", { route: route.key, attempt: attempt, idempotency_key: key })

        begin
          raw = send_once(request, timeout_ms, deadline, max_bytes)
        rescue Oblodai::Error => e
          raise e unless @retry.retry?(e, attempt: attempt, safe_to_repeat: safe_to_repeat)

          pause(e, attempt, deadline)
          attempt += 1
          next
        end

        return raw if raw.status >= 200 && raw.status < 300

        failure = classify(route, raw)
        @logger.debug("response", { route: route.key, status: raw.status,
                                    code: failure.code, request_id: failure.request_id })
        next if resign_for_skew?(route, raw, failure, skew, signed_offset)
        raise failure unless @retry.retry?(failure, attempt: attempt, safe_to_repeat: safe_to_repeat)

        pause(failure, attempt, deadline)
        attempt += 1
      end
    end

    def build_request(route, payload, key, path_params, query)
      RequestBuilder.build(
        base_url: @base_url, route: route, body: payload, ts: @clock.now,
        user_agent: @user_agent, path_params: path_params, query: query,
        credentials: @credentials, idempotency_key: key,
        extra_headers: @headers,
        # Never on a signed merchant route: the admin token provisions merchants, and a gateway
        # operator's token must not travel on every call a merchant integration makes.
        admin_token: route.auth == :onboard ? @admin_token : nil
      )
    end

    # A 401 the core attributes to the timestamp or the MAC gets exactly one re-signed attempt.
    # @return [Boolean] whether to try again with a corrected clock
    def resign_for_skew?(route, raw, failure, skew, signed_offset)
      return false unless raw.status == 401 && SIGNATURE_FAILURE_CODES.include?(failure.code)

      if skew[:tried]
        # The corrected timestamp did not help, so it was not skew — but only this call's own
        # correction may be undone; a sibling's newer one stays.
        @clock.revert_if_unchanged(skew[:installed], skew[:before])
        return false
      end

      offset = correct_skew(route, raw, signed_offset)
      return false if offset.nil?

      skew.merge!(tried: true, before: signed_offset, installed: offset)
      true
    end

    # Clock skew: the core rejected the timestamp/MAC. Learn its time from the `Date` header and
    # re-sign once. Measured against the offset THIS attempt signed with, not the live one: when
    # several calls fail together the first to recover fixes the shared clock, and the rest must
    # still re-sign their own stale request instead of concluding "the clock is already right".
    # @return [Integer, nil] the offset that was installed, or nil when no correction was made
    def correct_skew(route, raw, signed_offset)
      offset = @clock.observe_server_date(raw.header("date"))
      return nil if offset.nil? || (offset - signed_offset).abs <= Signing::SKEW_SECONDS / 2

      @logger.warn("clock skew detected; re-signing with server time",
                   { route: route.key, offset_sec: offset })
      @clock.correct(offset)
      offset
    end

    def resolve_idempotency_key(route, key)
      if key.nil?
        return route.idempotent ? Idempotency.new_key : nil
      end

      Idempotency.assert_key!(key)
      unless route.idempotent
        # The core ignores the header here, so a key would only make the SDK believe a re-send is
        # deduplicated when it is not — the one belief that turns a lost response into a double spend.
        raise ConfigError.new(
          "sdk.idempotency_unsupported",
          "#{route.key} does not deduplicate by Idempotency-Key; remove idempotency_key from this call",
          "idempotency_key"
        )
      end
      key
    end

    def describe_credentials(credentials)
      credentials ? "#{credentials.public_id} (secret [redacted])" : "none"
    end

    def classify(route, raw)
      decoded = Envelope.decode(raw.status, raw.body, retry_after: raw.header("retry-after"),
                                                      location: raw.header("location"))
      return decoded.error unless decoded.ok?

      ContractError.new("#{route.key}: HTTP #{raw.status} with a success envelope", raw.status, raw.body)
    rescue Oblodai::Error => e
      e
    end

    def pause(error, attempt, deadline)
      ms = @retry.delay_ms(error, attempt: attempt)
      if Util.monotonic_ms + ms > deadline
        raise TransportError.new(
          "transport.deadline",
          "retry would exceed the call deadline; last error: #{error.message}",
          cause_error: error
        )
      end
      sleep(ms / 1000.0) if ms.positive?
    end

    def send_once(request, timeout_ms, deadline, max_bytes)
      remaining = deadline - Util.monotonic_ms
      if remaining <= 0
        raise TransportError.new("transport.deadline", "the call deadline elapsed before the request was sent")
      end

      budget = [timeout_ms || @timeout_ms, remaining.ceil].min
      raw = @http.call(HTTP::Request.new(method: request.method, url: request.url,
                                         headers: request.headers, body: request.body,
                                         max_bytes: max_bytes),
                       timeout_ms: budget)
      assert_not_redirected!(request.url, raw)
      assert_within_cap!(request, raw, max_bytes)
      raw
    end

    # The SDK never follows a redirect: the signature is bound to the path it signed, and a 3xx to
    # another origin would replay the request (and its Idempotency-Key) somewhere else. An injected
    # adapter may follow one anyway, so the answer's own URL is checked against the one asked for.
    def assert_not_redirected!(requested, raw)
      landed = raw.url.to_s
      return if landed.empty? || landed == requested

      raise ContractError.new(
        "unexpected redirect: the request to #{requested} was answered by #{landed}; the SDK never " \
        "follows redirects — check base_url",
        0, nil, "sdk.bad_envelope"
      )
    end

    # An adapter that cannot stream hands back a body already in memory; the cap can only be checked
    # after the fact there, which still beats parsing an unbounded document.
    def assert_within_cap!(request, raw, max_bytes)
      size = raw.body.to_s.bytesize
      return if size <= max_bytes

      raise ContractError.new(
        "#{request.method} #{request.url}: response body exceeds #{max_bytes} bytes (saw #{size}) — " \
        "refusing to buffer it",
        raw.status, nil, "sdk.response_too_large"
      )
    end
  end
end
