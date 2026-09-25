# frozen_string_literal: true

# Spec §3 item 5: raw responses, hooks on request and response.
RSpec.describe "with_raw_response" do
  it "returns status, headers and request id, and parses on demand" do
    http = FakeHTTP.new([FakeHTTP.ok_for("createPayment", "uuid" => "u-1")
                           .merge(headers: { "x-request-id" => "srv-1", "x-extra" => "e" })])
    raw = client_with(http).payments.with_raw_response.create(amount: "1", currency: "USDT")
    expect(raw).to be_a(Oblodai::RawAPIResponse)
    expect(raw.status).to eq(200)
    expect(raw.header("X-Extra")).to eq("e")
    expect(raw.request_id).to eq("srv-1")
    expect(raw.parse).to be_a(Oblodai::Models::PaymentView)
    expect(raw.parse.uuid).to eq("u-1")
    expect(raw.parse).to equal(raw.parse) # parsed once
  end

  it "falls back to the request id the SDK sent" do
    http = FakeHTTP.new([FakeHTTP.ok_for("getBalance")])
    raw = client_with(http).account.with_raw_response.get_balance(request_id: "mine")
    expect(raw.request_id).to eq("mine")
  end

  it "still raises an error status" do
    http = FakeHTTP.new([FakeHTTP.api_error(404, { "code" => "payment.not_found", "retryable" => false })])
    expect { client_with(http).payments.with_raw_response.get_info(uuid: "u") }
      .to raise_error(Oblodai::NotFoundError)
  end

  it "leaves the namespace itself parsing" do
    http = FakeHTTP.new([FakeHTTP.ok_for("getBalance")])
    client = client_with(http)
    client.account.with_raw_response
    expect(client.account.get_balance).to be_a(Oblodai::Models::BalanceResult)
  end

  it "gives a file for a document and a page for a list" do
    http = FakeHTTP.new([
                          { status: 200, body: "%PDF", headers: { "content-type" => "application/pdf" } },
                          FakeHTTP.page([Samples.body("PaymentView", "uuid" => "p")], 0, 1, 50)
                        ])
    client = client_with(http)
    file = client.documents.with_raw_response.get_fees.parse
    expect(file).to be_a(Oblodai::FileResult)
    page = client.payments.with_raw_response.list_history
    expect(http.calls.size).to eq(2) # the raw call fetched the first page
    expect(page.parse.map(&:uuid)).to eq(["p"])
    expect(http.calls.size).to eq(2)
  end
end

RSpec.describe Oblodai::Hooks do
  it "calls on_request and on_response once per attempt, secrets redacted" do
    seen = []
    hooks = described_class.new(on_request: ->(info) { seen << [:request, info] },
                                on_response: ->(info) { seen << [:response, info] })
    http = FakeHTTP.new([FakeHTTP.html(503), FakeHTTP.ok_for("getBalance")])
    client_with(http, hooks: hooks, admin_token: "adm").account.get_balance(request_id: "rq")
    expect(seen.map(&:first)).to eq(%i[request response request response])
    first = seen[0][1]
    expect(first.attempt).to eq(1)
    expect(first.operation_id).to eq("getBalance")
    expect(first.request_id).to eq("rq")
    expect(first.url).to eq("https://api.test/v1/balance")
    expect(first.headers[SIGNING::HEADER_SIGNATURE]).to eq("[redacted]")
    expect(seen[2][1].attempt).to eq(2)
    expect(seen[1][1].status).to eq(503)
    expect(seen[1][1].error).to be_a(Oblodai::UnavailableError)
    expect(seen[3][1].status).to eq(200)
    expect(seen[3][1].error).to be_nil
    expect(seen[3][1].elapsed).to be >= 0
  end

  it "reports a transport failure as status 0" do
    responses = []
    hooks = described_class.new(on_response: ->(info) { responses << info })
    boom = Oblodai::TransportError.new("transport.network", "reset")
    http = FakeHTTP.new([{ raises: boom }])
    expect { client_with(http, hooks: hooks).payments.cancel(uuid: "u") }.to raise_error(Oblodai::TransportError)
    expect(responses.map(&:status)).to eq([0])
    expect(responses.first.error).to equal(boom)
  end

  it "refuses something that cannot be called" do
    expect { described_class.new(on_request: "nope") }.to raise_error(ArgumentError)
    expect { client_with(FakeHTTP.new([]), hooks: { on_request: -> {} }) }.to raise_error(Oblodai::ConfigError)
  end
end
