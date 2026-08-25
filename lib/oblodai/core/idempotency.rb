# frozen_string_literal: true

require_relative "util"
require_relative "../errors"

module Oblodai
  # Idempotency keys. On create-type routes the core caches the first response per key for the
  # merchant and replays it on retries; a different body under the same key is a 409
  # `idempotency.key_reused`. The SDK generates a key once per logical call and reuses it on every
  # retry, so a timeout never turns into a double payout.
  module Idempotency
    MAX_KEY_LENGTH = 255
    PRINTABLE_ASCII = /\A[\x21-\x7e]+\z/

    module_function

    # @return [String] a fresh UUID v4 key
    def new_key
      Util.uuid
    end

    # Validate a caller-supplied key before it is signed and sent.
    # @param key [String]
    # @raise [Oblodai::ValidationError]
    # @return [void]
    def assert_key!(key)
      invalid!("idempotency_key must be a non-empty string") unless key.is_a?(String) && !key.empty?
      invalid!("idempotency_key is too long (max #{MAX_KEY_LENGTH} chars)") if key.length > MAX_KEY_LENGTH
      # Header values must be visible ASCII: the key is signed verbatim, so a stray control char or
      # surrounding whitespace would silently change the MAC on one side only.
      return if PRINTABLE_ASCII.match?(key)

      invalid!("idempotency_key must be printable ASCII without spaces")
    end

    def invalid!(message)
      raise ValidationError.new(code: "sdk.bad_idempotency_key", message: message,
                                http_status: 0, retryable: false, field: "idempotency_key")
    end
  end
end
