# frozen_string_literal: true

require_relative "request"
require_relative "signing"

module Oblodai
  # Request and response hooks: plain callables the client calls once per attempt, for metrics,
  # tracing and structured logs. They run on the calling thread, so keep them cheap; an exception a
  # hook raises propagates out of the call.
  #
  #     hooks = Oblodai::Hooks.new(
  #       on_request: ->(info) { puts "#{info.method} #{info.url} attempt #{info.attempt}" },
  #       on_response: ->(info) { puts "#{info.status} in #{info.elapsed.round(3)}s" }
  #     )
  #     client = Oblodai::Client.new(hooks: hooks)
  Hooks = Struct.new(:on_request, :on_response, keyword_init: true) do
    def initialize(*)
      super
      [on_request, on_response].each do |hook|
        next if hook.nil? || hook.respond_to?(:call)

        raise ArgumentError, "a hook must respond to #call (got #{hook.class})"
      end
      freeze
    end
  end

  # One attempt about to be sent.
  #
  # @!attribute [r] headers
  #   @return [Hash{String => String}] as sent, with the signature and the admin token redacted
  # @!attribute [r] attempt
  #   @return [Integer] 1 for the first attempt, 2 for the first retry, and so on
  # @!attribute [r] request_id
  #   @return [String] `X-Request-ID` of the call; the same on every attempt
  # @!attribute [r] operation_id
  #   @return [String] the route's OpenAPI `operationId`
  RequestInfo = Struct.new(:method, :url, :headers, :attempt, :request_id, :operation_id, keyword_init: true) do
    def initialize(*)
      super
      freeze
    end
  end

  # How one attempt ended: an HTTP response, or `status == 0` and a transport `error`.
  #
  # @!attribute [r] elapsed
  #   @return [Float] seconds from sending the attempt to this point
  # @!attribute [r] error
  #   @return [Oblodai::Error, nil] the error this attempt ended with, else nil
  ResponseInfo = Struct.new(:request, :status, :headers, :elapsed, :error, keyword_init: true) do
    def initialize(*)
      super
      freeze
    end
  end

  # @!visibility private
  module HookSupport
    SECRET_HEADERS = [Signing::HEADER_SIGNATURE, RequestBuilder::HEADER_ADMIN_TOKEN].map(&:downcase).freeze

    module_function

    # A copy with the signature and the admin token replaced by "[redacted]".
    # @return [Hash{String => String}]
    def redact_headers(headers)
      headers.to_h { |name, value| [name, SECRET_HEADERS.include?(name.to_s.downcase) ? "[redacted]" : value] }.freeze
    end
  end
end
