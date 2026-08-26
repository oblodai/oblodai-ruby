# frozen_string_literal: true

require "time"

module Oblodai
  # Injectable clock for signing. The core rejects timestamps more than ±300 s from its own time;
  # a host with a drifting clock would get `merchant.bad_signature` on every call. The transport
  # learns the server's time from the `Date` header of a signature-failure response, re-signs once,
  # and keeps the offset only if that re-signed attempt got past authentication.
  class Clock
    # Offsets beyond this are implausible clock drift and are ignored (a broken proxy `Date`).
    MAX_PLAUSIBLE_OFFSET_SECONDS = 24 * 3600

    # @param base [#call] returns the local unix time in seconds
    def initialize(base = -> { Time.now.to_i })
      @base = base
      @offset = 0
      # The offset is shared by every thread using this client; a Mutex makes the read-compare-write
      # of {#revert_if_unchanged} atomic and keeps a torn read impossible on any Ruby.
      @lock = Mutex.new
    end

    # @return [Integer] server-minus-local offset currently applied, seconds
    def offset
      @lock.synchronize { @offset }
    end

    # @return [Integer] current unix time in seconds, corrected by the learned offset
    def now
      @base.call + offset
    end

    # Measure the offset from a response `Date` header.
    # @param date_header [String, nil]
    # @return [Integer, nil] nil when absent, unparsable or implausible
    def observe_server_date(date_header)
      return nil if date_header.nil? || date_header.empty?

      server = parse_http_date(date_header)
      return nil if server.nil?

      offset = server - @base.call
      offset.abs > MAX_PLAUSIBLE_OFFSET_SECONDS ? nil : offset
    end

    # Both spellings a gateway may put in `Date`: the HTTP-date the RFC asks for, and whatever
    # else a proxy decided to send.
    # @return [Integer, nil] unix seconds
    def parse_http_date(value)
      Time.httpdate(value).to_i
    rescue ArgumentError
      begin
        Time.parse(value).to_i
      rescue ArgumentError
        nil
      end
    end

    # @param offset_sec [Integer]
    # @return [void]
    def correct(offset_sec)
      @lock.synchronize { @offset = offset_sec }
    end

    # Undo a correction only when nobody else has moved the clock since. The offset is shared by
    # every in-flight call on the client; an unconditional revert would throw away a sibling call's
    # good correction and send the whole client back into `merchant.bad_signature`.
    #
    # @param installed [Integer] the offset this call put in place
    # @param previous [Integer] what was in force before it did
    # @return [Boolean] whether the revert happened
    def revert_if_unchanged(installed, previous)
      @lock.synchronize do
        next false unless @offset == installed

        @offset = previous
        true
      end
    end

    # @return [void]
    def reset
      correct(0)
    end
  end
end
