# frozen_string_literal: true

require "json"

# A fake HTTP adapter: replays scripted responses in order and records every request it saw.
# It implements the whole seam the SDK needs (`call(request, timeout_ms:)`), so the unit and
# contract suites exercise the real signing, envelope, retry and pagination code with no sockets.
class FakeHTTP
  Recorded = Struct.new(:verb, :url, :headers, :body, :timeout_ms, keyword_init: true) do
    # @return [Hash] the JSON body that was sent, parsed
    def json
      body.nil? ? nil : JSON.parse(body)
    end

    # @return [Hash{String => String}] query parameters of the URL
    def query
      URI.decode_www_form(URI.parse(url).query.to_s).to_h
    end

    def path
      URI.parse(url).path
    end
  end

  # @return [Array<Recorded>]
  attr_reader :calls

  # @param script [Array<Hash>] each entry: status:, body:, headers:, raises:, delay_ms:
  def initialize(script = [])
    @script = script.dup
    @calls = []
  end

  def call(request, timeout_ms:)
    @calls << Recorded.new(
      verb: request.method, url: request.url, body: request.body, timeout_ms: timeout_ms,
      headers: request.headers.each_with_object({}) { |(k, v), out| out[k.to_s.downcase] = v }
    )
    step = @script.shift
    raise "FakeHTTP: no scripted response for #{request.method} #{request.url}" if step.nil?
    raise step[:raises] if step[:raises]

    if step[:delay_ms]
      if step[:delay_ms] > timeout_ms
        raise Oblodai::TransportError.new("transport.timeout", "request timed out after #{timeout_ms} ms")
      end

      sleep(step[:delay_ms] / 1000.0)
    end

    body = step[:body].is_a?(String) || step[:body].nil? ? step[:body].to_s : JSON.generate(step[:body])
    headers = { "content-type" => "application/json" }.merge(step[:headers] || {})
    Oblodai::HTTP::Response.new(status: step[:status] || 200, headers: headers, body: body)
  end

  # @return [Hash] a success envelope step
  def self.ok(result = {})
    { status: 200, body: { "state" => 0, "result" => result } }
  end

  # @return [Hash] an error envelope step
  def self.api_error(status, error, headers = {})
    { status: status, body: { "error" => error }, headers: headers }
  end

  # @return [Hash] an answer with no Oblodai envelope, as a proxy or load balancer would send
  def self.html(status, headers = {})
    { status: status, body: "<html>upstream error</html>",
      headers: { "content-type" => "text/html" }.merge(headers) }
  end

  # @return [Hash] one page of a list result
  def self.page(items, offset, total, per_page)
    ok("items" => items,
       "paginate" => { "total" => total, "per_page" => per_page, "offset" => offset,
                       "has_pages" => offset + items.size < total })
  end
end
