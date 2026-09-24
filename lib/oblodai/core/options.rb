# frozen_string_literal: true

require_relative "../errors"

module Oblodai
  # Overrides for one call: the five call options every generated method takes as keywords. A
  # field left nil falls back to the client's setting.
  #
  # @!attribute [r] idempotency_key
  #   @return [String, nil] your own key; generated automatically on routes the core deduplicates,
  #     refused (`sdk.idempotency_unsupported`) on routes it does not
  # @!attribute [r] timeout
  #   @return [Numeric, nil] per-attempt timeout in seconds (capped by the client's `deadline`)
  # @!attribute [r] max_retries
  #   @return [Integer, nil] retries after the first attempt for this call
  # @!attribute [r] extra_headers
  #   @return [Hash, nil] headers for this call alone, merged over the client's own
  # @!attribute [r] request_id
  #   @return [String, nil] sent as `X-Request-ID` to tie your logs to ours; a UUID when omitted
  RequestOptions = Struct.new(:idempotency_key, :timeout, :max_retries, :extra_headers, :request_id,
                              keyword_init: true) do
    def initialize(*)
      super
      freeze
    end

    # Refuse unusable values before anything is signed or sent.
    # @raise [Oblodai::ConfigError]
    # @return [self]
    def validate!
      Oblodai::RequestOptions.check_timeout!(timeout, "timeout") unless timeout.nil?
      unless max_retries.nil? || (max_retries.is_a?(Integer) && !max_retries.negative?)
        raise ConfigError.new("sdk.bad_config", "max_retries must be a non-negative Integer", "max_retries")
      end
      unless extra_headers.nil? || extra_headers.is_a?(Hash)
        raise ConfigError.new("sdk.bad_config", "extra_headers must be a Hash", "extra_headers")
      end
      unless request_id.nil? || (request_id.is_a?(String) && /\A[\x21-\x7e]{1,255}\z/.match?(request_id))
        raise ConfigError.new("sdk.bad_config",
                              "request_id must be 1-255 printable ASCII characters without spaces",
                              "request_id")
      end
      self
    end

    # A timeout is a positive, finite number of seconds. Integer and Float both are fine (it is not
    # money); a String or a zero is a mistake worth naming.
    # @return [Numeric] the value
    # @raise [Oblodai::ConfigError]
    def self.check_timeout!(value, field)
      return value if value.is_a?(Numeric) && !value.is_a?(Complex) && value.to_f.finite? && value.positive?

      raise ConfigError.new("sdk.bad_config",
                            "#{field} must be a positive number of seconds (got #{value.inspect})", field)
    end
  end
end
