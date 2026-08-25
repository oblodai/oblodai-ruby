# frozen_string_literal: true

# The paths where a wrong decision costs money: a write re-sent after an ambiguous failure, an
# idempotency key that does not deduplicate, a list that quietly replays page one.
RSpec.describe "paths that could double-spend" do
  it "rejects a caller idempotency key on a route the core does not deduplicate" do
    http = FakeHTTP.new([FakeHTTP.ok({})])
    expect { client_with(http).payouts.approve("p1", idempotency_key: "k1") }
      .to raise_error(Oblodai::ConfigError) { |e| expect(e.code).to eq("sdk.idempotency_unsupported") }
    expect(http.calls).to be_empty
  end

  it "never re-sends an unsafe write after a proxy 503 without an envelope" do
    http = FakeHTTP.new([FakeHTTP.html(503), FakeHTTP.ok({})])
    error = nil
    begin
      client_with(http).payouts.approve("p1")
    rescue Oblodai::Error => e
      error = e
    end
    expect(error.http_status).to eq(503)
    expect(error).to be_synthetic
    expect(error).to be_retryable
    expect(http.calls.size).to eq(1)
  end

  it "retries a read route after a proxy 502/504 and honours the Retry-After header" do
    http = FakeHTTP.new([
                          FakeHTTP.html(502),
                          FakeHTTP.html(504, "retry-after" => "0"),
                          FakeHTTP.ok("balance" => { "merchant" => [] })
                        ])
    client_with(http).account.balance
    expect(http.calls.size).to eq(3)

    one = FakeHTTP.new([FakeHTTP.html(429, "retry-after" => "120")])
    error = nil
    begin
      client_with(one, retry_policy: { max_retries: 0 }).account.balance
    rescue Oblodai::Error => e
      error = e
    end
    expect(error.retry_after).to eq(120)
  end

  it "retries an enveloped retryable error on an unsafe write (the core answered, so it did nothing)" do
    http = FakeHTTP.new([
                          FakeHTTP.api_error(409, { "code" => "payout.funds_maturing", "retryable" => true,
                                                    "retry_after" => 0 }),
                          FakeHTTP.ok("uuid" => "p")
                        ])
    client_with(http).payouts.approve("p1")
    expect(http.calls.size).to eq(2)
  end
end

RSpec.describe Oblodai::Page do
  it "requests nothing until it is consumed" do
    http = FakeHTTP.new([FakeHTTP.api_error(404, { "code" => "payment.not_found", "retryable" => false })])
    page = client_with(http).payments.history
    expect(http.calls).to be_empty
    expect { page.first_page }
      .to raise_error(Oblodai::NotFoundError) { |e| expect(e.code).to eq("payment.not_found") }
    expect(http.calls.size).to eq(1)
  end

  it "does not forward a caller idempotency key to list pages" do
    http = FakeHTTP.new([FakeHTTP.page([], 0, 0, 50)])
    client_with(http).payouts.history(idempotency_key: "k").first_page
    expect(http.calls[0].headers).not_to have_key("idempotency-key")
  end
end

RSpec.describe "clock skew" do
  let(:far_date) { { "date" => Time.at(Time.now.to_i + 4000).httpdate } }

  it "ignores the Date header on a 401 that is not a signature failure" do
    http = FakeHTTP.new([FakeHTTP.api_error(401, { "code" => "auth.ip_not_allowed", "retryable" => false },
                                            far_date)])
    expect { client_with(http, retry_policy: { max_retries: 0 }).account.balance }
      .to raise_error(Oblodai::AuthenticationError) { |e| expect(e.code).to eq("auth.ip_not_allowed") }
    expect(http.calls.size).to eq(1)
  end

  it "reverts the correction when the re-signed attempt is still rejected, so one bad Date cannot wedge the client" do
    bad = { "code" => "merchant.bad_signature", "retryable" => false }
    http = FakeHTTP.new([
                          FakeHTTP.api_error(401, bad, far_date),
                          FakeHTTP.api_error(401, bad, far_date),
                          FakeHTTP.ok("balance" => { "merchant" => [] })
                        ])
    client = client_with(http, retry_policy: { max_retries: 0 })
    expect { client.account.balance }.to raise_error(Oblodai::AuthenticationError)
    client.account.balance
    expect(http.calls[2].headers["x-timestamp"].to_i).to be_within(5).of(Time.now.to_i)
  end
end

RSpec.describe "request construction" do
  it "keeps a path prefix on base_url and signs over the full path" do
    http = FakeHTTP.new([FakeHTTP.ok("balance" => { "merchant" => [] })])
    client_with(http, base_url: "https://gw.corp/oblodai/").account.balance
    expect(http.calls[0].url).to eq("https://gw.corp/oblodai/v1/balance")
  end

  it "drops caller headers that collide with signed headers" do
    http = FakeHTTP.new([FakeHTTP.ok("balance" => { "merchant" => [] })])
    client_with(http, headers: { "x-signature" => "zz", "X-Trace" => "t1" }).account.balance
    expect(http.calls[0].headers["x-signature"]).to match(/\A[0-9a-f]{64}\z/)
    expect(http.calls[0].headers["x-trace"]).to eq("t1")
  end

  it "refuses path parameters that would rewrite the URL" do
    client = client_with(FakeHTTP.new([]))
    ["..", ".", "a/b", ""].each do |bad|
      expect { client.payments.public_view(bad) }
        .to raise_error(Oblodai::ConfigError) { |e| expect(e.code).to eq("sdk.bad_path_param") }
    end
  end

  it "percent-encodes a path parameter instead of letting it change the request line" do
    http = FakeHTTP.new([FakeHTTP.ok({})])
    client_with(http).payments.public_view("a b?c=1")
    expect(http.calls[0].url).to eq("https://api.test/v1/pay/a%20b%3Fc%3D1")
  end

  it "sends uuid for document reports keyed by batch/link id" do
    http = FakeHTTP.new([{ status: 200, body: "%PDF", headers: { "content-type" => "application/pdf" } }])
    client_with(http).documents.batch_report("b-1", format: "csv")
    expect(http.calls[0].query).to include("uuid" => "b-1", "format" => "csv")
  end

  it "returns document bytes with their content type and filename" do
    http = FakeHTTP.new([{ status: 200, body: "%PDF-1.7",
                           headers: { "content-type" => "application/pdf",
                                      "content-disposition" => 'attachment; filename="statement.pdf"' } }])
    file = client_with(http).documents.statement(from: "2026-01-01", to: "2026-02-01")
    expect(file.content_type).to eq("application/pdf")
    expect(file.filename).to eq("statement.pdf")
    expect(file.bytes).to start_with("%PDF")
  end
end

RSpec.describe "deadlines, redirects and serialization" do
  it "stops retrying when the overall deadline would be exceeded" do
    http = FakeHTTP.new([
                          FakeHTTP.api_error(503, { "code" => "db.unavailable", "retryable" => true,
                                                    "retry_after" => 2 }),
                          FakeHTTP.ok({})
                        ])
    error = nil
    begin
      client_with(http, deadline_ms: 100).account.balance
    rescue Oblodai::Error => e
      error = e
    end
    expect(error.code).to eq("transport.deadline")
    expect(http.calls.size).to eq(1)
  end

  it "names the redirect target instead of a bare envelope error" do
    http = FakeHTTP.new([{ status: 301, body: "",
                           headers: { "location" => "https://www.api.test/v1/balance" } }])
    error = nil
    begin
      client_with(http, retry_policy: { max_retries: 0 }).account.balance
    rescue Oblodai::Error => e
      error = e
    end
    expect(error.http_status).to eq(301)
    expect(error.message).to match(/redirect.*www\.api\.test/)
  end

  it "serializes errors without the raw body and keeps the message" do
    http = FakeHTTP.new([FakeHTTP.api_error(400, { "code" => "payment.below_minimum",
                                                   "message" => "too small", "retryable" => false })])
    error = nil
    begin
      client_with(http).payments.create(amount: "0", currency: "USDT")
    rescue Oblodai::Error => e
      error = e
    end
    json = JSON.parse(error.to_json)
    expect(json).to include("code" => "payment.below_minimum", "message" => "too small",
                            "http_status" => 400)
    expect(json).not_to have_key("raw")
    expect(error.inspect).not_to include("too small ")
    expect(error.raw_body).to include("error")
  end

  it "raises a ContractError when a 200 body is not an envelope" do
    http = FakeHTTP.new([{ status: 200, body: "<html>hi</html>", headers: { "content-type" => "text/html" } }])
    expect { client_with(http).account.balance }
      .to raise_error(Oblodai::ContractError) { |e| expect(e.code).to eq("sdk.bad_envelope") }
  end

  it "surfaces an idempotent replay the core could not cache" do
    http = FakeHTTP.new([FakeHTTP.ok("ok" => true, "idempotent_replay" => true,
                                     "detail" => "response too large")])
    expect { client_with(http).payments.create(amount: "1", currency: "USDT") }
      .to raise_error(Oblodai::ContractError, /already processed/)
  end
end
