# frozen_string_literal: true

require_relative "generated/enums"

# Every failure the SDK can raise, and the mapping from the core's error envelope onto them.
module Oblodai
  # Error model. One family, {Oblodai::Error}, mirrors the core's error envelope:
  #
  #     { "error": { "code", "message", "field"?, "details"?, "retryable", "retry_after"?, "request_id"? } }
  #
  # `retryable` is authoritative when the core wrote the envelope: it is the core's own
  # classification of the failure. A response without an envelope (a proxy 502, an HTML 503) is
  # `synthetic` — the core never saw or never answered the request — and is retried only when
  # repeating is safe. Subclasses exist for `rescue` ergonomics; the discriminator is always #code.
  class Error < StandardError
    # @return [String] stable machine code (`family.reason`), e.g. "payout.insufficient_funds"
    attr_reader :code
    # @return [Integer] HTTP status, or 0 when no response was received
    attr_reader :http_status
    # @return [Integer, nil] seconds to wait before retrying, when the core (or a Retry-After
    #   header) provided a hint
    attr_reader :retry_after
    # @return [String, nil] server-side request id — quote it when contacting support
    attr_reader :request_id
    # @return [String, nil] the request field the error refers to, for validation failures
    attr_reader :field
    # @return [Hash{String => String}, nil] machine-readable facts about the refusal, keys documented
    #   by its code (e.g. "cli.permission_denied" carries "required_role" and "role"); nil when absent
    attr_reader :details
    # @return [Object, nil] the wrapped lower-level exception, when there was one
    attr_reader :cause_error
    # @return [String] the bare description, without the `[code]` prefix and the request id that
    #   {#message} carries
    attr_reader :text

    # @param code [String]
    # @param message [String]
    # @param http_status [Integer]
    # @param retryable [Boolean]
    # @param retry_after [Integer, nil]
    # @param request_id [String, nil]
    # @param field [String, nil]
    # @param details [Hash{String => String}, nil]
    # @param synthetic [Boolean] true when no core envelope was present (proxy/LB answer)
    # @param raw [Object, nil] decoded error body, or the raw text when it was not JSON
    # @param cause_error [Exception, nil]
    def initialize(code:, message:, http_status: 0, retryable: false, retry_after: nil,
                   request_id: nil, field: nil, synthetic: false, raw: nil, cause_error: nil, details: nil)
      # `to_s`/`message` is what a log line shows: the code and the request id travel with the text.
      super(request_id ? "[#{code}] #{message} (request_id=#{request_id})" : "[#{code}] #{message}")
      @text = message
      @code = code
      @http_status = http_status
      @retryable = retryable
      @retry_after = retry_after
      @request_id = request_id
      @field = field
      @details = details
      @synthetic = synthetic
      @raw = raw
      @cause_error = cause_error
    end

    # Whether repeating the identical request can succeed later.
    # @return [Boolean]
    def retryable?
      @retryable
    end

    # No core envelope: the answer came from something in front of the core.
    # @return [Boolean]
    def synthetic?
      @synthetic
    end

    # The raw error body. Deliberately not a plain attribute and never part of {#to_h}, {#inspect}
    # or {#to_s}: a logger that dumps an exception must not print a response body.
    # @return [Object, nil]
    def raw_body
      @raw
    end

    # Code family ("payout" in "payout.insufficient_funds").
    # @return [String]
    def family
      dot = @code.index(".")
      dot.nil? ? @code : @code[0...dot]
    end

    # Structured-logger friendly: keeps the message, drops the raw body.
    # @return [Hash{Symbol => Object}]
    def to_h
      {
        error: self.class.name, code: @code, message: @text, http_status: @http_status,
        retryable: @retryable, retry_after: @retry_after, request_id: @request_id, field: @field,
        details: @details, synthetic: @synthetic
      }
    end

    # @return [String] JSON without the raw body
    def to_json(*)
      require "json"
      to_h.to_json(*)
    end

    def inspect
      "#<#{self.class.name} code=#{@code.inspect} http_status=#{@http_status} " \
        "retryable=#{@retryable} message=#{@text.inspect}>"
    end
  end

  # The request never produced an HTTP response: DNS, TCP, TLS, timeout, abort, deadline.
  class TransportError < Error
    # Codes: "transport.timeout", "transport.network", "transport.aborted", "transport.deadline".
    def initialize(code, message, cause_error: nil)
      super(code: code, message: message, http_status: 0,
            retryable: ["transport.timeout", "transport.network"].include?(code),
            cause_error: cause_error)
    end
  end

  # Raised before any request is sent: bad options, missing credentials, unusable arguments.
  class ConfigError < Error
    def initialize(code, message, field = nil)
      super(code: code, message: message, http_status: 0, retryable: false, field: field)
    end
  end

  # The core (or something in front of it) answered with an error status.
  class ApiError < Error; end

  # 400 — the request is malformed or violates a business rule; see #field and #code.
  class ValidationError < ApiError; end
  # 401 — bad signature, unknown key, clock skew, IP not in the allow-list.
  class AuthenticationError < ApiError; end
  # 403 — the key is valid but not allowed to do this (feature disabled, IP not allowlisted).
  class PermissionError < ApiError; end
  # 404 — the referenced object does not exist for this merchant.
  class NotFoundError < ApiError; end
  # 409 — state or idempotency conflict.
  class ConflictError < ApiError; end
  # 409 "idempotency.key_reused" — the same key was used with a different request body.
  class IdempotencyConflictError < ConflictError; end
  # 429 — rate limited; #retry_after is set.
  class RateLimitError < ApiError; end
  # 503 — an upstream dependency is down; safe to retry after a pause.
  class UnavailableError < ApiError; end
  # 5xx other than 503.
  class InternalError < ApiError; end

  # The response could not be interpreted as the documented envelope.
  class ContractError < Error
    # @param code [String] "sdk.bad_envelope", or a narrower contract-family code
    def initialize(message, http_status, raw = nil, code = "sdk.bad_envelope")
      super(code: code, message: message, http_status: http_status,
            retryable: false, raw: raw)
    end
  end

  # The delivery's signature verified but its body is not a usable event. Deliberately NOT a
  # {SignatureError}: a receiver that answers 401 to signature failures must not answer 401 here —
  # the sender is authentic and the delivery should be retried or investigated, not rejected as
  # forged.
  class WebhookPayloadError < ContractError
    def initialize(message, raw = nil)
      super(message, 0, raw, "webhook.bad_payload")
    end
  end

  # Webhook verification failed (bad signature, stale timestamp, missing headers).
  class SignatureError < Error
    def initialize(code, message)
      super(code: code, message: message, http_status: 0, retryable: false)
    end
  end

  # Error class per HTTP status.
  STATUS_ERRORS = {
    400 => ValidationError, 401 => AuthenticationError, 403 => PermissionError,
    404 => NotFoundError, 409 => ConflictError, 429 => RateLimitError, 503 => UnavailableError
  }.freeze

  # Upper bound for any retry hint the SDK will report, seconds. A hostile or broken peer can put
  # anything in `retry_after` / `Retry-After`; clamping here means no caller ever schedules a wait
  # from a negative, infinite or overflowing number. The retry loop separately honours at most
  # `RetryPolicy#max_retry_after_ms` (default 30 s) of it.
  MAX_RETRY_AFTER_SECONDS = 86_400

  # A retry hint as whole seconds, or nil when the value carries no usable number. Integers, floats
  # and numeric strings are accepted (the core writes an integer; a proxy may not); anything else —
  # a boolean, a hash, "soon", NaN — is not an instruction and is dropped.
  # @return [Integer, nil] clamped to [0, MAX_RETRY_AFTER_SECONDS]
  def self.coerce_retry_after(value)
    seconds = case value
              when Integer then value
              when Float then value.finite? ? value : nil
              when String then numeric_string(value)
              end
    return nil if seconds.nil?

    # Ruby integers are arbitrary precision, so a 400-digit hint cannot overflow — it is clamped
    # like any other out-of-range number.
    seconds.clamp(0, MAX_RETRY_AFTER_SECONDS).ceil
  end

  # @return [Numeric, nil]
  def self.numeric_string(value)
    v = value.strip
    return nil if v.empty?
    return Integer(v, 10) if /\A[+-]?\d+\z/.match?(v)

    f = Float(v, exception: false)
    f&.finite? ? f : nil
  end

  # @return [String, nil] the value when it is a string, nil otherwise
  def self.string_or_nil(value)
    value.is_a?(String) ? value : nil
  end

  # @return [Hash{String => String}, nil] the string values of `details`; nil when there are none
  def self.details_or_nil(value)
    return nil unless value.is_a?(Hash)

    out = value.select { |k, v| k.is_a?(String) && v.is_a?(String) }
    out.empty? ? nil : out.freeze
  end

  # Decode `{"error": {...}}` field by field. A peer that answers with the right shape but the wrong
  # types (`code: 123`, `retryable: "yes"`) must not be able to change how the SDK behaves: an
  # unusable `code` demotes the whole body to "no envelope", and every other field falls back to the
  # value the HTTP status alone justifies. Never raises.
  #
  # @param raw [Object] the `error` member of the body, whatever it turned out to be
  # @return [Array(Hash, Boolean)] the decoded detail and whether it is usable as an envelope
  def self.decode_error_detail(raw)
    src = raw.is_a?(Hash) ? raw : {}
    request_id = string_or_nil(src["request_id"])
    code = string_or_nil(src["code"])
    return [{ "request_id" => request_id }, false] if code.nil? || code.empty?

    detail = {
      "code" => code,
      "message" => string_or_nil(src["message"]),
      "field" => string_or_nil(src["field"]),
      "details" => details_or_nil(src["details"]),
      "request_id" => request_id
    }
    # Only a literal boolean is the core's classification; anything else leaves the decision to the
    # status, which is what a body without the field gets.
    detail["retryable"] = src["retryable"] if [true, false].include?(src["retryable"])
    detail["retry_after"] = coerce_retry_after(src["retry_after"])
    [detail, true]
  end

  # Statuses a response without an envelope may carry transiently (LB/proxy/timeouts).
  TRANSIENT_STATUSES = [408, 425, 429, 500, 502, 503, 504].freeze

  # `retryable` is the core's own classification when it wrote the envelope; without one, only a
  # transient status can be retried.
  # @return [Boolean]
  def self.retryable?(http_status, detail, synthetic)
    return TRANSIENT_STATUSES.include?(http_status) if synthetic
    return detail["retryable"] if [true, false].include?(detail["retryable"])

    [429, 503].include?(http_status)
  end

  # Build the right subclass from an error envelope (or a synthesized one) and the HTTP status.
  # The detail is expected to have come from {decode_error_detail}; a hand-built one is decoded the
  # same way, so no path into this method can bypass the type checks.
  #
  # @param http_status [Integer]
  # @param detail [Hash] the `error` object of the envelope, string-keyed
  # @param raw [Object, nil] the decoded body (kept off every serialization)
  # @param synthetic [Boolean] no `{error}` envelope was present
  # @param retry_after_header [Integer, nil] parsed `Retry-After`, seconds
  # @return [Oblodai::ApiError]
  def self.api_error_from(http_status, detail, raw: nil, synthetic: false, retry_after_header: nil)
    code = string_or_nil(detail["code"]).to_s.empty? ? "internal" : detail["code"]
    message = string_or_nil(detail["message"])
    args = {
      code: code,
      message: message.nil? || message.empty? ? "HTTP #{http_status} (#{code})" : message,
      http_status: http_status, retryable: retryable?(http_status, detail, synthetic),
      retry_after: coerce_retry_after(detail["retry_after"]) || coerce_retry_after(retry_after_header),
      request_id: string_or_nil(detail["request_id"]), field: string_or_nil(detail["field"]),
      details: synthetic ? nil : details_or_nil(detail["details"]),
      synthetic: synthetic, raw: raw
    }
    error_class(http_status, code).new(**args)
  end

  # Which subclass a status maps to. The code wins over the status for the one conflict worth
  # separating: a reused idempotency key is not the same failure as a state conflict.
  # @return [Class]
  def self.error_class(http_status, code)
    return IdempotencyConflictError if code == Enums::ErrorCode::IDEMPOTENCY_KEY_REUSED

    STATUS_ERRORS.fetch(http_status) { http_status >= 500 ? InternalError : ApiError }
  end
end
