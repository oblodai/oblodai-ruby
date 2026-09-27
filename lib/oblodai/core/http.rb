# frozen_string_literal: true

require "net/http"
require "uri"
require_relative "../errors"

module Oblodai
  # The HTTP seam. Everything above it deals in {Oblodai::HTTP::Response}; everything below it is
  # replaceable — pass any object with `#call(request, timeout:)` as `http:` to the client
  # (a proxy-aware Net::HTTP, an instrumented wrapper, a fake in tests).
  module HTTP
    # What an adapter is handed.
    #
    # @!attribute [r] max_bytes
    #   @return [Integer, nil] the largest body the SDK will accept for this route. An adapter that
    #     can stream should stop reading past it; one that cannot may ignore it — the transport
    #     checks the size of whatever comes back either way.
    #
    # @!attribute [r] display_url
    #   @return [String, nil] `url` with secret path and query values (a claim token, a signed link's
    #     `sig`) replaced by "[redacted]" — what an adapter should name in its errors and logs
    Request = Struct.new(:method, :url, :headers, :body, :max_bytes, :display_url, keyword_init: true) do
      # Method and redacted URL only: the headers carry the signature.
      def inspect
        "#<Oblodai::HTTP::Request #{method} #{display_url || "[redacted]"}>"
      end
      alias_method :to_s, :inspect

      def pretty_print(printer)
        printer.text(inspect)
      end
    end

    # What an adapter must return. `headers` is a plain Hash; look values up with {#header}, which
    # is case-insensitive the way HTTP is.
    #
    # @!attribute [r] url
    #   @return [String, nil] the URL the answer actually came from, when the adapter knows it. The
    #     SDK never follows redirects; a value different from the one requested means the adapter
    #     did, and the transport refuses the answer.
    Response = Struct.new(:status, :headers, :body, :url, keyword_init: true) do
      def initialize(*)
        super
        freeze
      end

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
    # redirects never followed (a redirect is a configuration error, not a hop), the response body
    # streamed with a hard ceiling so a mistargeted base URL cannot be buffered into an OOM.
    class NetHTTPAdapter
      # @param open_timeout [Numeric, nil] connect timeout, seconds; defaults to the per-attempt timeout
      def initialize(open_timeout: nil)
        @open_timeout = open_timeout
      end

      # @param request [Oblodai::HTTP::Request]
      # @param timeout [Numeric] seconds for the whole attempt
      # @return [Oblodai::HTTP::Response]
      # @raise [Oblodai::TransportError]
      # @raise [Oblodai::ContractError] when the answer exceeds `request.max_bytes`
      def call(request, timeout:)
        uri = URI.parse(request.url)
        timeout = [timeout.to_f, 0.001].max
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = @open_timeout || timeout
        http.read_timeout = timeout
        http.write_timeout = timeout
        # Net::HTTP retries an idempotent request once by itself when the connection is dropped
        # before the answer. The SDK owns that decision — it knows which routes may be repeated —
        # so the transparent retry is switched off: a GET must not leave twice per attempt.
        http.max_retries = 0

        req = build(request, uri)
        # The budget covers the WHOLE answer, not each socket read: Net::HTTP's read_timeout resets
        # on every chunk, so a peer trickling one byte at a time could hold the call open forever.
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
        http.start { |session| read_response(session, req, request, deadline) }
      rescue Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout => e
        raise TransportError.new("transport.timeout", "request timed out after #{timeout.round(3)} s", cause_error: e)
      rescue SystemCallError, SocketError, OpenSSL::SSL::SSLError, IOError, Net::ProtocolError => e
        raise TransportError.new("transport.network", "network error: #{scrub(e.message, request)}", cause_error: e)
      end

      private

      # Stream the body, stopping the moment the cap is passed: the timeout above covers the whole
      # read, not just the first byte, so a peer sending one byte a minute cannot hold the call open.
      def read_response(session, req, request, deadline)
        max_bytes = request.max_bytes
        label = request.display_url || "#{request.method} [redacted]"
        session.request(req) do |response|
          declared = response["content-length"].to_s
          if max_bytes && /\A\d+\z/.match?(declared) && declared.to_i > max_bytes
            raise too_large(label, declared.to_i, max_bytes)
          end

          body = +""
          body.force_encoding(Encoding::BINARY)
          response.read_body do |chunk|
            body << chunk.b
            raise too_large(label, body.bytesize, max_bytes) if max_bytes && body.bytesize > max_bytes
            raise Net::ReadTimeout if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
          end
          return Response.new(status: response.code.to_i, headers: flatten(response), body: body,
                              url: req.uri&.to_s)
        end
      end

      # An error text from Net::HTTP or OpenSSL with the request's secret-bearing URL swapped for its
      # display form.
      def scrub(text, request)
        return text if request.display_url.nil?

        origin = %r{\A[a-z][a-z0-9+.-]*://[^/]*}i
        [[request.url, request.display_url], [request.url.sub(origin, ""), request.display_url.sub(origin, "")]]
          .reject { |secret, shown| secret.empty? || secret == shown }
          .reduce(text.to_s) { |out, (secret, shown)| out.gsub(secret, shown) }
      end

      def too_large(label, seen, max_bytes)
        ContractError.new(
          "#{label}: response body exceeds #{max_bytes} bytes (saw at least #{seen}) — " \
          "refusing to buffer it",
          0, nil, "sdk.response_too_large"
        )
      end

      def build(request, uri)
        klass = request.method == "GET" ? Net::HTTP::Get : Net::HTTP::Post
        req = klass.new(uri)
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
