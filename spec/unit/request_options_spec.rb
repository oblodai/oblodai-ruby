# frozen_string_literal: true

# Spec §3 items 2 and 9: the five call options are explicit keywords, timeouts are seconds, and every
# call carries its own X-Request-ID.
RSpec.describe "call options" do
  let(:balance) { FakeHTTP.ok_for("getBalance") }

  it "sends a UUID X-Request-ID on every call, the same one on every attempt of a call" do
    http = FakeHTTP.new([FakeHTTP.html(503), balance, balance])
    client = client_with(http)
    client.account.get_balance
    client.account.get_balance
    ids = http.calls.map { |call| call.headers["x-request-id"] }
    expect(ids).to all(match(/\A[0-9a-f-]{36}\z/))
    expect(ids[0]).to eq(ids[1]) # the retry keeps the call's id
    expect(ids[2]).not_to eq(ids[0])
  end

  it "sends the caller's request_id, or the X-Request-ID header the caller set" do
    http = FakeHTTP.new([balance, balance, balance])
    client_with(http).account.get_balance(request_id: "order-42")
    client_with(http, headers: { "x-request-id" => "from-client" }).account.get_balance
    client_with(http).account.get_balance(extra_headers: { "X-Request-ID" => "from-call" })
    expect(http.calls.map { |call| call.headers["x-request-id"] }).to eq(%w[order-42 from-client from-call])
  end

  it "refuses a request_id that cannot travel in a header" do
    http = FakeHTTP.new([])
    ["", "a b", "x\ny", 42].each do |bad|
      expect { client_with(http).account.get_balance(request_id: bad) }
        .to raise_error(Oblodai::ConfigError) { |e| expect(e.field).to eq("request_id") }
    end
    expect(http.calls).to be_empty
  end

  it "takes max_retries per call" do
    http = FakeHTTP.new([FakeHTTP.html(503), FakeHTTP.html(503), FakeHTTP.html(503), balance])
    expect { client_with(http).account.get_balance(max_retries: 0) }.to raise_error(Oblodai::UnavailableError)
    expect(http.calls.size).to eq(1)
    client_with(http, retry_policy: { max_retries: 0, base_delay_ms: 1, max_delay_ms: 1 })
      .account.get_balance(max_retries: 2)
    expect(http.calls.size).to eq(4)
  end

  it "merges extra_headers over the client's headers for one call" do
    http = FakeHTTP.new([balance, balance])
    client = client_with(http, headers: { "X-Team" => "a", "X-Keep" => "k" })
    client.account.get_balance(extra_headers: { "X-Team" => "b" })
    client.account.get_balance
    expect(http.calls[0].headers).to include("x-team" => "b", "x-keep" => "k")
    expect(http.calls[1].headers).to include("x-team" => "a")
  end

  it "refuses a timeout that is not a positive number of seconds" do
    http = FakeHTTP.new([])
    [0, -1, "5", Float::INFINITY].each do |bad|
      expect { client_with(http).account.get_balance(timeout: bad) }
        .to raise_error(Oblodai::ConfigError) { |e| expect(e.field).to eq("timeout") }
    end
    expect { client_with(http, timeout: 0) }.to raise_error(Oblodai::ConfigError)
    expect(http.calls).to be_empty
  end

  it "has no millisecond options any more" do
    expect { client_with(FakeHTTP.new([]), timeout_ms: 100) }.to raise_error(ArgumentError, /timeout_ms/)
    expect { client_with(FakeHTTP.new([])).account.get_balance(timeout_ms: 100) }
      .to raise_error(ArgumentError, /timeout_ms/)
  end

  it "fills a route's own idempotency_key body field from the option instead of the header" do
    http = FakeHTTP.new([FakeHTTP.ok_for("sandboxFaucet")])
    client_with(http).sandbox.faucet(asset: "USDT", amount: "5", idempotency_key: "faucet-1")
    expect(http.calls[0].json).to include("idempotency_key" => "faucet-1")
    expect(http.calls[0].headers).not_to have_key("idempotency-key")
  end

  it "refuses the faucet key given twice — in params and as the keyword — before the network" do
    http = FakeHTTP.new([FakeHTTP.ok_for("sandboxFaucet")])
    sandbox = client_with(http).sandbox
    own = [
      { "asset" => "USDT", "amount" => "5", "idempotency_key" => "own" },
      Oblodai::Models::FaucetRequest.new(asset: "USDT", amount: "5", idempotency_key: "own")
    ]
    own.each do |params|
      expect { sandbox.faucet(params, idempotency_key: "faucet-2") }
        .to raise_error(ArgumentError, /idempotency_key/)
    end
    expect(http.calls).to be_empty
  end
end

RSpec.describe "Oblodai::Client#with_options" do
  it "returns a client with the overrides and leaves the original untouched" do
    http = FakeHTTP.new([FakeHTTP.ok_for("getBalance")] * 2)
    client = client_with(http, timeout: 10, headers: { "X-A" => "1" })
    patient = client.with_options(timeout: 60, max_retries: 5, extra_headers: { "X-B" => "2" })
    expect(patient).to be_a(Oblodai::Client)
    expect(patient.transport.timeout).to eq(60)
    expect(patient.transport.retry_policy.max_retries).to eq(5)
    expect(client.transport.timeout).to eq(10)
    patient.account.get_balance
    client.account.get_balance
    expect(http.calls[0].timeout).to eq(60.0)
    expect(http.calls[0].headers).to include("x-a" => "1", "x-b" => "2")
    expect(http.calls[1].timeout).to eq(10.0)
    expect(http.calls[1].headers).not_to have_key("x-b")
  end

  it "validates what it is given" do
    client = client_with(FakeHTTP.new([]))
    expect { client.with_options(timeout: -1) }.to raise_error(Oblodai::ConfigError)
    expect { client.with_options(max_retries: -1) }.to raise_error(Oblodai::ConfigError)
  end
end
