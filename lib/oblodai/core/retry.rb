# frozen_string_literal: true

require_relative "../errors"

module Oblodai
  # Retry policy. Two questions decide every retry:
  #
  # 1. Can it succeed? — the core's `retryable` flag (authoritative when the core wrote the
  #    envelope), or a transient status for answers that carry no envelope.
  # 2. Is repeating safe? — only for read-only routes and for writes the core deduplicates by
  #    Idempotency-Key. A write the core does not deduplicate is never re-sent once it MAY have
  #    reached the core: a transport error or a proxy 503 after the request left the socket could
  #    mean the payout already happened.
  #
  # An envelope error on an unsafe write is still retried when `retryable` — the core answered, so
  # it did not perform the operation (429/503/frozen/maturing all fail before any effect).
  # `Retry-After` always wins over the computed backoff; otherwise exponential backoff with jitter.
  class RetryPolicy
    # @return [Integer] maximum number of retries after the first attempt
    attr_reader :max_retries
    # @return [Integer] base delay for the first retry, ms
    attr_reader :base_delay_ms
    # @return [Integer] upper bound for a computed (non-Retry-After) delay, ms
    attr_reader :max_delay_ms
    # @return [Integer] upper bound honored for a server-provided Retry-After, ms
    attr_reader :max_retry_after_ms

    def initialize(max_retries: 2, base_delay_ms: 250, max_delay_ms: 4_000,
                   max_retry_after_ms: 30_000, random: Random.new)
      @max_retries = max_retries
      @base_delay_ms = base_delay_ms
      @max_delay_ms = max_delay_ms
      @max_retry_after_ms = max_retry_after_ms
      @random = random
      # A Random instance is not thread-safe, and one policy is shared by every call on a client.
      @random_lock = Mutex.new
    end

    # @param overrides [Hash] any of the keyword arguments above
    # @return [Oblodai::RetryPolicy]
    def with(**overrides)
      self.class.new(
        max_retries: overrides.fetch(:max_retries, @max_retries),
        base_delay_ms: overrides.fetch(:base_delay_ms, @base_delay_ms),
        max_delay_ms: overrides.fetch(:max_delay_ms, @max_delay_ms),
        max_retry_after_ms: overrides.fetch(:max_retry_after_ms, @max_retry_after_ms),
        random: overrides.fetch(:random, @random)
      )
    end

    # @param error [Exception]
    # @param attempt [Integer] 0 for the first retry decision (after attempt #1 failed)
    # @param safe_to_repeat [Boolean] true when re-sending cannot duplicate a side effect
    # @return [Boolean]
    def retry?(error, attempt:, safe_to_repeat:)
      return false if attempt >= @max_retries
      return false unless error.is_a?(Oblodai::Error)
      return false unless error.retryable?
      return safe_to_repeat if error.is_a?(TransportError)
      # No core envelope: something in front of the core answered; the core may have done the work.
      return safe_to_repeat if error.synthetic?

      true
    end

    # Delay before the next attempt, in ms.
    # @param error [Exception]
    # @param attempt [Integer]
    # @return [Integer]
    def delay_ms(error, attempt:)
      if error.is_a?(Oblodai::Error) && error.retry_after&.to_i&.positive?
        return [error.retry_after.to_i * 1000, @max_retry_after_ms].min
      end

      exp = [@max_delay_ms, @base_delay_ms * (2**attempt)].min
      # Full jitter with a floor so a burst of retries never lands in the same instant.
      [(exp / 4.0).floor, jitter(exp.to_i + 1)].max
    end

    private

    # @return [Integer]
    def jitter(bound)
      @random_lock.synchronize { @random.rand(bound) }
    end
  end
end
