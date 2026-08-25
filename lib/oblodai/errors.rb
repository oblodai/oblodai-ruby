# frozen_string_literal: true

# Every failure the SDK can raise, and the mapping from the core's error envelope onto them.
module Oblodai
  # Error model. One family, {Oblodai::Error}, mirrors the core's error envelope:
  #
  #     { "error": { "code", "message", "field"?, "retryable", "retry_after"?, "request_id"? } }
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
    # @return [Object, nil] the wrapped lower-level exception, when there was one
    attr_reader :cause_error

    # @param code [String]
    # @param message [String]
    # @param http_status [Integer]
    # @param retryable [Boolean]
    # @param retry_after [Integer, nil]
    # @param request_id [String, nil]
    # @param field [String, nil]
    # @param synthetic [Boolean] true when no core envelope was present (proxy/LB answer)
    # @param raw [Object, nil] decoded error body, or the raw text when it was not JSON
    # @param cause_error [Exception, nil]
    def initialize(code:, message:, http_status: 0, retryable: false, retry_after: nil,
                   request_id: nil, field: nil, synthetic: false, raw: nil, cause_error: nil)
      super(message)
      @code = code
      @http_status = http_status
      @retryable = retryable
      @retry_after = retry_after
      @request_id = request_id
      @field = field
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
        error: self.class.name, code: @code, message: message, http_status: @http_status,
        retryable: @retryable, retry_after: @retry_after, request_id: @request_id, field: @field,
        synthetic: @synthetic
      }
    end

    # @return [String] JSON without the raw body
    def to_json(*args)
      require "json"
      to_h.to_json(*args)
    end

    def inspect
      "#<#{self.class.name} code=#{@code.inspect} http_status=#{@http_status} " \
        "retryable=#{@retryable} message=#{message.inspect}>"
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
  # 403 — the key is valid but not allowed to do this (wrong key kind, feature disabled).
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
    def initialize(message, http_status, raw = nil)
      super(code: "sdk.bad_envelope", message: message, http_status: http_status,
            retryable: false, raw: raw)
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

  # Statuses a response without an envelope may carry transiently (LB/proxy/timeouts).
  TRANSIENT_STATUSES = [408, 425, 429, 500, 502, 503, 504].freeze

  # `retryable` is the core's own classification when it wrote the envelope; without one, only a
  # transient status can be retried.
  # @return [Boolean]
  def self.retryable?(http_status, detail, synthetic)
    return TRANSIENT_STATUSES.include?(http_status) if synthetic
    return detail["retryable"] == true if detail.key?("retryable")

    [429, 503].include?(http_status)
  end

  # Build the right subclass from an error envelope (or a synthesized one) and the HTTP status.
  #
  # @param http_status [Integer]
  # @param detail [Hash] the `error` object of the envelope, string-keyed
  # @param raw [Object, nil] the decoded body (kept off every serialization)
  # @param synthetic [Boolean] no `{error}` envelope was present
  # @param retry_after_header [Integer, nil] parsed `Retry-After`, seconds
  # @return [Oblodai::ApiError]
  def self.api_error_from(http_status, detail, raw: nil, synthetic: false, retry_after_header: nil)
    code = detail["code"].to_s.empty? ? "internal" : detail["code"]
    args = {
      code: code,
      message: if detail["message"].to_s.empty?
                 "request failed with HTTP #{http_status} " \
                   "(#{synthetic ? "no envelope" : code})"
               else
                 detail["message"]
               end,
      http_status: http_status, retryable: retryable?(http_status, detail, synthetic),
      retry_after: detail["retry_after"] || retry_after_header,
      request_id: detail["request_id"], field: detail["field"],
      synthetic: synthetic, raw: raw
    }
    error_class(http_status, code).new(**args)
  end

  # Which subclass a status maps to. The code wins over the status for the one conflict worth
  # separating: a reused idempotency key is not the same failure as a state conflict.
  # @return [Class]
  def self.error_class(http_status, code)
    return IdempotencyConflictError if code == "idempotency.key_reused"

    STATUS_ERRORS.fetch(http_status) { http_status >= 500 ? InternalError : ApiError }
  end
end
