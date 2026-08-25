# frozen_string_literal: true

require "securerandom"

module Oblodai
  # Small helpers shared by the core. Nothing here knows about the API.
  module Util
    module_function

    # RFC 4122 v4 UUID from the platform CSPRNG.
    # @return [String]
    def uuid
      SecureRandom.uuid
    end

    # Constant-time string equality (both sides are hex, so byte length equals char length).
    # @return [Boolean]
    def secure_compare(left, right)
      a = left.to_s.b
      b = right.to_s.b
      return false unless a.bytesize == b.bytesize

      OpenSSL.fixed_length_secure_compare(a, b)
    rescue NoMethodError # Ruby without the OpenSSL helper
      diff = 0
      a.each_byte.zip(b.each_byte) { |x, y| diff |= x ^ y }
      diff.zero?
    end

    # Case-insensitive header lookup over any of the header shapes a Rack/Rails/Net::HTTP caller
    # may hand us: a Hash of strings, a Hash of arrays, or anything responding to #[].
    #
    # @param headers [Hash, #[], nil]
    # @param name [String]
    # @return [String, nil]
    def header_value(headers, name)
      return nil if headers.nil?

      want = name.downcase
      return first_of(headers[name] || headers[want]) unless headers.respond_to?(:each_pair)

      headers.each_pair do |key, value|
        return first_of(value) if key.to_s.downcase == want || rack_key(key) == want
      end
      nil
    end

    # Header values reach us as a String or as an Array of them (Rack, Net::HTTP).
    # @return [String, nil]
    def first_of(value)
      value = value.first if value.is_a?(Array)
      value&.to_s
    end

    # Rack passes headers as HTTP_X_WEBHOOK_SIGNATURE; accept that spelling too.
    # @return [String]
    def rack_key(key)
      key.to_s.sub(/\AHTTP_/, "").downcase.tr("_", "-")
    end

    # Drop nil values so they never reach the JSON body as explicit nulls.
    # @param hash [Hash, nil]
    # @return [Hash]
    def compact(hash)
      return {} if hash.nil?

      hash.compact
    end

    # Symbolize the keys of a decoded JSON object, one level deep.
    # @return [Hash{Symbol => Object}]
    def symbolize(hash)
      hash.each_with_object({}) { |(k, v), out| out[k.to_sym] = v }
    end

    # Monotonic milliseconds — immune to a wall-clock jump during a retry loop.
    # @return [Float]
    def monotonic_ms
      Process.clock_gettime(Process::CLOCK_MONOTONIC) * 1000.0
    end
  end
end
