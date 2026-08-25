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

    # @return [String]
    attr_reader :base_url

    # @param base_url [String]
    # @param user_agent [String]
    # @param credentials [Oblodai::RequestBuilder::Credentials, nil] payment/`any` routes
    # @param payout_credentials [Oblodai::RequestBuilder::Credentials, nil] payout routes
    # @param http [#call] HTTP adapter
    # @param timeout_ms [Integer] per-attempt timeout
    # @param deadline_ms [Integer] overall budget per call, including retries and pauses
    # @param retry_policy [Oblodai::RetryPolicy]
    # @param clock [Oblodai::Clock]
    # @param logger [#debug]
    # @param headers [Hash] extra headers on every request
    # @param admin_token [String, nil] sent as X-Admin-Token on `onboard` routes only
    def initialize(base_url:, user_agent:, credentials: nil, payout_credentials: nil, http: nil,
                   timeout_ms: 30_000, deadline_ms: 90_000, retry_policy: RetryPolicy.new,
                   clock: Clock.new, logger: NullLogger.new, headers: {}, admin_token: nil)
      @base_url = base_url
      @user_agent = user_agent
      @credentials = credentials
      @payout_credentials = payout_credentials
      @http = http || HTTP::NetHTTPAdapter.new
      @timeout_ms = timeout_ms
      @deadline_ms = deadline_ms
      @retry = retry_policy
      @clock = clock
      @logger = logger
      @headers = headers || {}
      @admin_token = admin_token
    end

    # Call an envelope route and return its `result`.
    #
    # @param route [Oblodai::Contract::Route]
    # @return [Object] the decoded `result`
    # @raise [Oblodai::Error]
    def call(route, body: nil, query: nil, path_params: nil, idempotency_key: nil,
             prefer_payout_key: false, timeout_ms: nil, deadline_ms: nil)
      raw = execute(route, body: body, query: query, path_params: path_params,
                           idempotency_key: idempotency_key, prefer_payout_key: prefer_payout_key,
                           timeout_ms: timeout_ms, deadline_ms: deadline_ms)
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

    # Which key pair signs a route. `any` routes take the payment key unless told otherwise.
    def credentials_for(route, prefer_payout)
      return @payout_credentials || @credentials if route.auth == :payout || (route.auth == :any && prefer_payout)

      @credentials
    end

    def execute(route, body: nil, query: nil, path_params: nil, idempotency_key: nil,
                prefer_payout_key: false, timeout_ms: nil, deadline_ms: nil)
      payload = RequestBuilder.serialize_body(body, route.method)
      key = resolve_idempotency_key(route, idempotency_key)
      safe_to_repeat = route.safe || (route.idempotent && !key.nil?)
      deadline = Util.monotonic_ms + (deadline_ms || @deadline_ms)

      attempt = 0
      skew_tried = false
      skew_before = 0
      loop do
        request = RequestBuilder.build(
          base_url: @base_url, route: route, body: payload, ts: @clock.now,
          user_agent: @user_agent, path_params: path_params, query: query,
          credentials: credentials_for(route, prefer_payout_key), idempotency_key: key,
          extra_headers: extra_headers_for(route)
        )
        @logger.debug("request", { route: route.key, attempt: attempt, idempotency_key: key })

        begin
          raw = send_once(request, timeout_ms, deadline)
        rescue Oblodai::Error => e
          raise e unless @retry.retry?(e, attempt: attempt, safe_to_repeat: safe_to_repeat)

          pause(e, attempt, deadline)
          attempt += 1
          next
        end

        return raw if raw.status >= 200 && raw.status < 300

        failure = classify(route, raw)
        @logger.debug("response", Logging.redact({ route: route.key, status: raw.status,
                                                   code: failure.code, request_id: failure.request_id }))

        if raw.status == 401 && SIGNATURE_FAILURE_CODES.include?(failure.code)
          if skew_tried
            @clock.correct(skew_before) # the corrected timestamp did not help: it was not skew
          elsif (skew_before = correct_skew(route, raw))
            skew_tried = true
            next
          end
        end

        raise failure unless @retry.retry?(failure, attempt: attempt, safe_to_repeat: safe_to_repeat)

        pause(failure, attempt, deadline)
        attempt += 1
      end
    end

    # Clock skew: the core rejected the timestamp/MAC. Learn its time from the `Date` header and
    # re-sign once; the caller keeps the previous offset so it can be reverted when that attempt is
    # rejected too — one bad proxy `Date` must not wedge the client.
    # @return [Integer, nil] the offset that was in force before the correction, or nil if none was made
    def correct_skew(route, raw)
      offset = @clock.observe_server_date(raw.header("date"))
      return nil if offset.nil? || (offset - @clock.offset).abs <= Signing::SKEW_SECONDS / 2

      @logger.warn("clock skew detected; re-signing with server time",
                   { route: route.key, offset_sec: offset })
      previous = @clock.offset
      @clock.correct(offset)
      previous
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

    def extra_headers_for(route)
      return @headers unless route.auth == :onboard && @admin_token

      @headers.merge("X-Admin-Token" => @admin_token)
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

    def send_once(request, timeout_ms, deadline)
      remaining = deadline - Util.monotonic_ms
      if remaining <= 0
        raise TransportError.new("transport.deadline", "the call deadline elapsed before the request was sent")
      end

      budget = [timeout_ms || @timeout_ms, remaining.ceil].min
      @http.call(HTTP::Request.new(method: request.method, url: request.url,
                                   headers: request.headers, body: request.body),
                 timeout_ms: budget)
    end
  end
end
