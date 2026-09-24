# frozen_string_literal: true

require_relative "request"

module Oblodai
  # The raw side of a successful call: `resource.with_raw_response.<method>(...)`. Status, headers
  # and request id of the 2xx answer; {#parse} gives the value the method returns without
  # `with_raw_response`. An error status still raises, exactly as without it.
  class RawAPIResponse
    # @return [Oblodai::RouteSpec]
    attr_reader :route

    # @param route [Oblodai::RouteSpec]
    # @param answer [Oblodai::Transport::Answer]
    # @param decode [#call] turns the answer into the value the method returns
    def initialize(route, answer, decode)
      @route = route
      @answer = answer
      @decode = decode
      @lock = Mutex.new
    end

    # @return [Integer]
    def status
      @answer.response.status
    end

    # @return [Hash{String => String}]
    def headers
      @answer.response.headers
    end

    # One header, looked up case-insensitively.
    # @return [String, nil]
    def header(name)
      @answer.response.header(name)
    end

    # @return [String] the response's `X-Request-ID`, else the one this SDK sent with the call
    def request_id
      header(RequestBuilder::HEADER_REQUEST_ID) || @answer.request_id
    end

    # @return [String] the body bytes
    def body
      @answer.response.body
    end

    # The value the method returns without `with_raw_response` (computed once).
    # @return [Object]
    def parse
      @lock.synchronize do
        @parsed = @decode.call(@answer) unless defined?(@parsed)
        @parsed
      end
    end

    def inspect
      "#<Oblodai::RawAPIResponse status=#{status} request_id=#{request_id.inspect} route=#{@route.key.inspect}>"
    end
  end
end
