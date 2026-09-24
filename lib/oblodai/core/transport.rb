# frozen_string_literal: true

require_relative "clock"
require_relative "envelope"
require_relative "hooks"
require_relative "http"
require_relative "idempotency"
require_relative "logger"
require_relative "options"
require_relative "request"
require_relative "retry"
require_relative "signing"
require_relative "util"
require_relative "../errors"

module Oblodai
  # The HTTP engine every resource goes through. {#call} does the whole lifecycle of one call:
  # serialize → sign → send (with timeout) → decode envelope → classify error → retry per policy.
  # {#call_raw} returns the 2xx answer itself (documents, raw responses).
  class Transport
    # Error codes that mean the core rejected the signature because of the timestamp or MAC.
    SIGNATURE_FAILURE_CODES = ["merchant.bad_signature", "auth.bad_timestamp"].freeze

    # Response body caps. The SDK buffers the whole body, so an endless or mistargeted stream would
    # otherwise grow until the process dies. JSON envelopes are small; `bare` routes are PDFs and CSV
    # statements.
    MAX_JSON_BODY_BYTES = 8 * 1024 * 1024
    MAX_BARE_BODY_BYTES = 64 * 1024 * 1024

    # Everything one call may carry and override.
    #
    # @!attribute [r] timeout
    #   @return [Numeric, nil] per-attempt timeout, seconds; the transport's own when nil
    # @!attribute [r] max_retries
    #   @return [Integer, nil] retries after the first attempt; the policy's when nil
    # @!attribute [r] request_id
    #   @return [String, nil] `X-Request-ID` of every attempt; a caller header, else a UUID, when nil
    CallOptions = Struct.new(:body, :query, :path_params, :idempotency_key, :timeout, :max_retries,
                             :extra_headers, :request_id, keyword_init: true) do
      def initialize(*)
        super
        freeze
      end

      # @param options [Oblodai::RequestOptions]
      # @return [Oblodai::Transport::CallOptions]
      def self.from(options, body: nil, query: nil, path_params: nil)
        options ||= RequestOptions.new
        new(body: body, query: query, path_params: path_params, idempotency_key: options.idempotency_key,
            timeout: options.timeout, max_retries: options.max_retries,
            extra_headers: options.extra_headers, request_id: options.request_id)
      end
    end

    # A 2xx answer and the `X-Request-ID` the call was sent with.
    Answer = Struct.new(:response, :request_id, keyword_init: true) do
      def initialize(*)
        super
        freeze
      end
    end

    # @return [String]
    attr_reader :base_url
    # @return [Numeric] per-attempt timeout, seconds
    attr_reader :timeout
    # @return [Numeric] budget for the whole call including retries and pauses, seconds
    attr_reader :deadline
    # @return [Oblodai::Hooks, nil]
    attr_reader :hooks

    # @param base_url [String]
    # @param user_agent [String]
    # @param credentials [Oblodai::RequestBuilder::Credentials, nil] the merchant's one API key;
    #   it signs every route the core gates with `key`
    # @param http [#call] HTTP adapter: `call(Oblodai::HTTP::Request, timeout:)` → {Oblodai::HTTP::Response}
    # @param timeout [Numeric] per-attempt timeout, seconds
    # @param deadline [Numeric] overall budget per call, including retries and pauses, seconds
    # @param retry_policy [Oblodai::RetryPolicy]
    # @param clock [Oblodai::Clock]
    # @param logger [#debug]
    # @param headers [Hash] extra headers on every request
    # @param admin_token [String, nil] sent as X-Admin-Token on `onboard` routes only
    # @param hooks [Oblodai::Hooks, nil] called once per attempt
    def initialize(base_url:, user_agent:, credentials: nil, http: nil, timeout: 30, deadline: 90,
                   retry_policy: RetryPolicy.new, clock: Clock.new, logger: NullLogger.new, headers: {},
                   admin_token: nil, hooks: nil)
      @base_url = base_url
      @user_agent = user_agent
      @credentials = credentials
      @http = http || HTTP::NetHTTPAdapter.new
      @timeout = RequestOptions.check_timeout!(timeout, "timeout")
      @deadline = RequestOptions.check_timeout!(deadline, "deadline")
      @retry = retry_policy
      @clock = clock
      # Wrapped, not trusted: whatever logger the caller injected receives fields that were redacted
      # before it saw them, so a pino-style sink cannot be the thing that prints a signing secret.
      @logger = Logging.redacting(logger)
      @headers = (headers || {}).dup.freeze
      @admin_token = admin_token
      @hooks = hooks
    end

    # A transport with these overridden that shares everything else — the HTTP adapter, the
    # credentials and the learned clock offset.
    # @param timeout [Numeric, nil] seconds per attempt
    # @param max_retries [Integer, nil]
    # @param extra_headers [Hash, nil] merged over this transport's headers
    # @return [Oblodai::Transport]
    def derive(timeout: nil, max_retries: nil, extra_headers: nil)
      RequestOptions.new(timeout: timeout, max_retries: max_retries, extra_headers: extra_headers).validate!
      self.class.new(
        base_url: @base_url, user_agent: @user_agent, credentials: @credentials, http: @http,
        timeout: timeout || @timeout, deadline: @deadline,
        retry_policy: max_retries.nil? ? @retry : @retry.with(max_retries: max_retries),
        clock: @clock, logger: @logger, headers: @headers.merge(extra_headers || {}),
        admin_token: @admin_token, hooks: @hooks
      )
    end

    # @return [Oblodai::RetryPolicy]
    def retry_policy
      @retry
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
    # @param route [Oblodai::RouteSpec]
    # @param options [Oblodai::Transport::CallOptions]
    # @return [Object] the decoded `result`
    # @raise [Oblodai::Error]
    def call(route, options = CallOptions.new)
      Transport.unwrap(route, execute(route, options).response)
    end

    # Call a route and return its 2xx answer as is (status already checked).
    # @return [Oblodai::Transport::Answer]
    def call_raw(route, options = CallOptions.new)
      execute(route, options)
    end

    # The `result` of a success envelope. The core replays a cached response by Idempotency-Key;
    # when the original was too large to cache it answers `{ok, idempotent_replay: true, detail}`
    # instead of the object — that is surfaced as an error, not handed over as the result.
    # @param route [Oblodai::RouteSpec]
    # @param response [Oblodai::HTTP::Response]
    # @return [Object]
    def self.unwrap(route, response)
      result = Envelope.decode(response.status, response.body).result
      if result.is_a?(Hash) && result["idempotent_replay"] == true
        raise ContractError.new(
          "#{route.key}: the request was already processed but its response was too large to " \
          "replay — fetch the result by order_id/reference (#{result["detail"]})",
          response.status, result
        )
      end
      result
    end

    # Pause between attempts. Its own method so a test can record pauses instead of sleeping them.
    # @param seconds [Float]
    # @return [void]
    def snooze(seconds)
      sleep(seconds)
    end

    private

    # One logical call: attempts, retries, skew correction.
    def execute(route, options)
      call = prepare(route, options)
      attempt = 0
      skew = { tried: false, before: 0, installed: 0 }

      loop do
        # The offset this attempt is signed with. Compared against the server's own time below —
        # never against the shared offset, which a concurrent call may already have corrected.
        signed_offset = @clock.offset
        request = build_request(route, call)
        info = announce(route, request, call, attempt)
        sent_at = Util.monotonic_ms

        begin
          raw = send_once(request, call, route)
        rescue Oblodai::Error => e
          report(info, 0, {}, sent_at, e)
          raise e unless call[:retry].retry?(e, attempt: attempt, safe_to_repeat: call[:safe])

          pause(e, attempt, call)
          attempt += 1
          next
        end

        if raw.status >= 200 && raw.status < 300
          report(info, raw.status, raw.headers, sent_at, nil)
          return Answer.new(response: raw, request_id: call[:request_id])
        end

        failure = classify(route, raw)
        report(info, raw.status, raw.headers, sent_at, failure)
        @logger.debug("response", { route: route.key, status: raw.status, code: failure.code,
                                    request_id: failure.request_id || call[:request_id] })
        next if resign_for_skew?(route, raw, failure, skew, signed_offset)
        raise failure unless call[:retry].retry?(failure, attempt: attempt, safe_to_repeat: call[:safe])

        pause(failure, attempt, call)
        attempt += 1
      end
    end

    # Everything decided once per call, before the first byte is signed.
    def prepare(route, options)
      RequestOptions.new(idempotency_key: nil, timeout: options.timeout, max_retries: options.max_retries,
                         extra_headers: options.extra_headers, request_id: options.request_id).validate!
      headers = options.extra_headers ? @headers.merge(options.extra_headers) : @headers
      key = resolve_idempotency_key(route, options.idempotency_key)
      {
        payload: RequestBuilder.serialize_body(options.body, route.method),
        options: options, headers: headers, key: key,
        # One id for every attempt: it names the call, not the attempt.
        request_id: options.request_id || Util.header_value(headers, RequestBuilder::HEADER_REQUEST_ID) ||
          Util.uuid,
        retry: options.max_retries.nil? ? @retry : @retry.with(max_retries: options.max_retries),
        safe: route.safe || (route.idempotent && !key.nil?),
        timeout: options.timeout || @timeout,
        deadline_at: Util.monotonic_ms + (@deadline * 1000.0)
      }
    end

    def build_request(route, call)
      options = call[:options]
      RequestBuilder.build(
        base_url: @base_url, route: route, body: call[:payload], ts: @clock.now,
        user_agent: @user_agent, path_params: options.path_params, query: options.query,
        credentials: @credentials, idempotency_key: call[:key],
        extra_headers: call[:headers], request_id: call[:request_id],
        # Never on a signed merchant route: the admin token provisions merchants, and a gateway
        # operator's token must not travel on every call a merchant integration makes.
        admin_token: route.auth == :onboard ? @admin_token : nil
      )
    end

    # Log the attempt and call the request hook.
    # @return [Oblodai::RequestInfo, nil]
    def announce(route, request, call, attempt)
      @logger.debug("request", { route: route.key, attempt: attempt, request_id: call[:request_id],
                                 idempotency_key: call[:key] })
      return nil if @hooks.nil?

      info = RequestInfo.new(method: request.method, url: request.url,
                             headers: HookSupport.redact_headers(request.headers), attempt: attempt + 1,
                             request_id: call[:request_id], operation_id: route.operation_id.to_s)
      @hooks.on_request&.call(info)
      info
    end

    def report(info, status, headers, sent_at, error)
      return if info.nil? || @hooks.on_response.nil?

      @hooks.on_response.call(ResponseInfo.new(request: info, status: status, headers: headers,
                                               elapsed: [(Util.monotonic_ms - sent_at) / 1000.0, 0.0].max,
                                               error: error))
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
    # re-sign once. Measured against the offset THIS attempt signed with, not the live one.
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

    def pause(error, attempt, call)
      ms = call[:retry].delay_ms(error, attempt: attempt)
      if Util.monotonic_ms + ms > call[:deadline_at]
        raise TransportError.new(
          "transport.deadline",
          "retry would exceed the call deadline; last error: #{error.message}",
          cause_error: error
        )
      end
      snooze(ms / 1000.0) if ms.positive?
    end

    def send_once(request, call, route)
      remaining = call[:deadline_at] - Util.monotonic_ms
      if remaining <= 0
        raise TransportError.new("transport.deadline", "the call deadline elapsed before the request was sent")
      end

      max_bytes = route.bare ? MAX_BARE_BODY_BYTES : MAX_JSON_BODY_BYTES
      budget = [call[:timeout].to_f, remaining / 1000.0].min
      raw = @http.call(HTTP::Request.new(method: request.method, url: request.url,
                                         headers: request.headers, body: request.body,
                                         max_bytes: max_bytes),
                       timeout: budget)
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
