# frozen_string_literal: true

require_relative "util"
require_relative "../errors"
require_relative "../generated/signing"

module Oblodai
  # Idempotency keys. On create-type routes the core caches the first response per key for the
  # merchant and replays it on retries; a different body under the same key is a 409
  # `idempotency.key_reused`. The SDK generates a key once per logical call and reuses it on every
  # retry, so a timeout never turns into a double payout.
  module Idempotency
    # Longest key the core accepts, characters (`x-oblodai-signing.max_idempotency_key_length`).
    MAX_KEY_LENGTH = Generated::SigningProtocol::MAX_IDEMPOTENCY_KEY_LENGTH
    PRINTABLE_ASCII = /\A[\x21-\x7e]+\z/

    module_function

    # @return [String] a fresh UUID v4 key
    def new_key
      Util.uuid
    end

    # Validate a caller-supplied key before it is signed and sent.
    # @param key [String]
    # @raise [Oblodai::ConfigError]
    # @return [void]
    def assert_key!(key)
      invalid!("idempotency_key must be a non-empty string") unless key.is_a?(String) && !key.empty?
      max = Generated::SigningProtocol::MAX_IDEMPOTENCY_KEY_LENGTH
      invalid!("idempotency_key is too long (max #{max} chars)") if key.length > max
      # Header values must be visible ASCII: the key is signed verbatim, so a stray control char or
      # surrounding whitespace would silently change the MAC on one side only.
      return if PRINTABLE_ASCII.match?(key)

      invalid!("idempotency_key must be printable ASCII without spaces")
    end

    # A key the SDK refuses is a caller mistake caught before anything is sent — a ConfigError, like
    # every other pre-flight refusal. A ValidationError would claim the API answered 400, and
    # callers branch on that difference.
    def invalid!(message)
      raise ConfigError.new("sdk.bad_idempotency_key", message, "idempotency_key")
    end
  end
end
