# frozen_string_literal: true

require "net/http"
require "uri"
require_relative "../errors"

module Oblodai
  # The HTTP seam. Everything above it deals in {Oblodai::HTTP::Response}; everything below it is
  # replaceable — pass any object with `#call(request, timeout_ms:)` as `http:` to the client
  # (a proxy-aware Net::HTTP, an instrumented wrapper, a fake in tests).
  module HTTP
    # What an adapter is handed.
    Request = Struct.new(:method, :url, :headers, :body, keyword_init: true)

    # What an adapter must return. `headers` is a plain Hash; look values up with {#header}, which
    # is case-insensitive the way HTTP is.
    Response = Struct.new(:status, :headers, :body, keyword_init: true) do
      # @param name [String]
      # @return [String, nil]
      def header(name)
        want = name.downcase
        headers.each { |k, v| return v.is_a?(Array) ? v.first : v if k.to_s.downcase == want }
        nil
      end

      # @return [String, nil]
      def content_type
        header("content-type")
      end
    end

    # Net::HTTP adapter: one connection per attempt, timeouts applied to connect, read and write,
    # redirects never followed (a redirect is a configuration error, not a hop).
    class NetHTTPAdapter
      # @param open_timeout_ms [Integer, nil] connect timeout; defaults to the per-attempt timeout
      def initialize(open_timeout_ms: nil)
        @open_timeout_ms = open_timeout_ms
      end

      # @param request [Oblodai::HTTP::Request]
      # @param timeout_ms [Integer]
      # @return [Oblodai::HTTP::Response]
      # @raise [Oblodai::TransportError]
      def call(request, timeout_ms:)
        uri = URI.parse(request.url)
        timeout = [timeout_ms, 1].max / 1000.0
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = (@open_timeout_ms ? @open_timeout_ms / 1000.0 : timeout)
        http.read_timeout = timeout
        http.write_timeout = timeout

        req = build(request, uri)
        response = http.start { |session| session.request(req) }
        Response.new(status: response.code.to_i, headers: flatten(response),
                     body: response.body.to_s.dup.force_encoding(Encoding::BINARY))
      rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout => e
        raise TransportError.new("transport.timeout", "request timed out after #{timeout_ms} ms", cause_error: e)
      rescue SystemCallError, SocketError, OpenSSL::SSL::SSLError, IOError, Net::ProtocolError => e
        raise TransportError.new("transport.network", "network error: #{e.message}", cause_error: e)
      end

      private

      def build(request, uri)
        klass = request.method == "GET" ? Net::HTTP::Get : Net::HTTP::Post
        req = klass.new(uri.request_uri)
        request.headers.each { |k, v| req[k] = v }
        req.body = request.body.to_s.b if request.body
        req
      end

      def flatten(response)
        out = {}
        response.each_header { |k, v| out[k] = v }
        out
      end
    end
  end
end
