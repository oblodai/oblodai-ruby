# frozen_string_literal: true

require "socket"

# The one component the fake adapter cannot stand in for: the real Net::HTTP seam, against a real
# socket. A raw TCP server is used rather than WEBrick so the suite keeps its zero dependencies.

# Serves exactly one request and returns what the client sent, so the test can assert on the wire.
class OneShotServer
  attr_reader :port

  def initialize(&responder)
    @server = TCPServer.new("127.0.0.1", 0)
    @port = @server.addr[1]
    @received = Queue.new
    @thread = Thread.new do
      socket = @server.accept
      @received << read_request(socket)
      socket.write(responder.call)
      socket.close
    rescue IOError, Errno::ECONNRESET
      nil
    end
  end

  # @return [String] the request as it arrived
  def request(timeout = 5)
    @received.pop(timeout: timeout) or raise "no request arrived"
  end

  def close
    @thread.kill
    @server.close unless @server.closed?
  end

  private

  def read_request(socket)
    head = +""
    head << socket.readpartial(4096) until head.include?("\r\n\r\n")
    length = head[/content-length:\s*(\d+)/i, 1].to_i
    body_start = head.split("\r\n\r\n", 2)[1].to_s
    head << socket.read(length - body_start.bytesize) if length > body_start.bytesize
    head
  end
end

RSpec.describe Oblodai::HTTP::NetHTTPAdapter do
  def with_server(response)
    server = OneShotServer.new { response }
    yield server
  ensure
    server&.close
  end

  def get(port, max_bytes: 1_000_000, path: "/v1/x")
    described_class.new.call(
      Oblodai::HTTP::Request.new(method: "GET", url: "http://127.0.0.1:#{port}#{path}",
                                 headers: { "Accept" => "application/json" }, body: nil,
                                 max_bytes: max_bytes),
      timeout_ms: 3000
    )
  end

  def http_response(body, status: "200 OK", extra: "")
    "HTTP/1.1 #{status}\r\nContent-Type: application/json\r\n" \
      "Content-Length: #{body.bytesize}\r\nConnection: close\r\n#{extra}\r\n#{body}"
  end

  it "sends the request and returns the answer" do
    with_server(http_response('{"state":0,"result":{"ok":true}}')) do |server|
      response = get(server.port)
      expect(response.status).to eq(200)
      expect(response.body).to eq('{"state":0,"result":{"ok":true}}')
      expect(response.content_type).to eq("application/json")
      expect(response.url).to eq("http://127.0.0.1:#{server.port}/v1/x")
      expect(server.request).to include("GET /v1/x HTTP/1.1", "Accept: application/json")
    end
  end

  it "puts the body and headers of a POST on the wire" do
    with_server(http_response('{"state":0,"result":{}}')) do |server|
      described_class.new.call(
        Oblodai::HTTP::Request.new(method: "POST", url: "http://127.0.0.1:#{server.port}/v1/payment",
                                   headers: { "Content-Type" => "application/json",
                                              "Idempotency-Key" => "k-1" },
                                   body: '{"amount":"1"}', max_bytes: 1_000_000),
        timeout_ms: 3000
      )
      wire = server.request
      expect(wire).to include("POST /v1/payment HTTP/1.1", "Idempotency-Key: k-1", '{"amount":"1"}')
    end
  end

  it "refuses a body whose declared length is over the cap, before reading it" do
    with_server(http_response("x" * 5000)) do |server|
      expect { get(server.port, max_bytes: 1000) }
        .to raise_error(Oblodai::ContractError) { |e| expect(e.code).to eq("sdk.response_too_large") }
    end
  end

  it "stops reading a body that has no declared length once it passes the cap" do
    # No Content-Length: the body runs until the peer closes, which is exactly the shape that used
    # to be buffered without limit.
    endless = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n#{"x" * 200_000}"
    with_server(endless) do |server|
      expect { get(server.port, max_bytes: 1000) }
        .to raise_error(Oblodai::ContractError) { |e| expect(e.code).to eq("sdk.response_too_large") }
    end
  end

  it "counts the whole body read against the timeout, not each chunk" do
    # Net::HTTP's read_timeout resets on every chunk that arrives, so a peer trickling bytes could
    # hold a call open for as long as it liked. The budget is the whole answer.
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    trickler = Thread.new do
      socket = server.accept
      socket.readpartial(4096)
      socket.write("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n")
      60.times do
        socket.write("x")
        socket.flush
        sleep 0.02
      end
    rescue IOError, Errno::EPIPE, Errno::ECONNRESET
      nil
    end

    request = Oblodai::HTTP::Request.new(method: "GET", url: "http://127.0.0.1:#{port}/v1/x",
                                         headers: {}, body: nil, max_bytes: 1_000_000)
    expect { described_class.new.call(request, timeout_ms: 200) }
      .to raise_error(Oblodai::TransportError) { |e| expect(e.code).to eq("transport.timeout") }
  ensure
    trickler&.kill
    server&.close
  end

  it "hands a redirect back rather than following it" do
    moved = "HTTP/1.1 302 Found\r\nLocation: http://example.invalid/v1\r\nContent-Length: 0\r\n" \
            "Connection: close\r\n\r\n"
    with_server(moved) do |server|
      response = get(server.port)
      expect(response.status).to eq(302)
      expect(response.header("location")).to eq("http://example.invalid/v1")
    end
  end

  it "reports a refused connection as a transport error" do
    port = TCPServer.open("127.0.0.1", 0) { |s| s.addr[1] } # a port nothing is listening on
    expect { get(port) }
      .to raise_error(Oblodai::TransportError) { |e| expect(e.code).to eq("transport.network") }
  end
end
