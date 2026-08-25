# frozen_string_literal: true

RSpec.describe Oblodai::Transport do
  it "signs path+query on GET and sends no body" do
    http = FakeHTTP.new([FakeHTTP.page([], 0, 0, 10)])
    client_with(http).sandbox.webhooks(limit: 10, offset: 0).first_page
    call = http.calls.first
    expect(call.url).to eq("https://api.test/v1/sandbox/webhooks?limit=10&offset=0")
    expect(call.body).to be_nil
    expect(call.headers["x-public-id"]).to eq("pk_test_1")
    expect(call.headers["x-signature"]).to match(/\A[0-9a-f]{64}\z/)
    expect(call.headers["x-timestamp"].to_i).to be_within(5).of(Time.now.to_i)
  end

  it "generates one Idempotency-Key per create call and reuses it across retries" do
    http = FakeHTTP.new([
                          FakeHTTP.api_error(503, { "code" => "db.unavailable", "message" => "down",
                                                    "retryable" => true }),
                          FakeHTTP.ok("uuid" => "u")
                        ])
    client_with(http).payments.create(amount: "1", currency: "USDT")
    expect(http.calls.size).to eq(2)
    key = http.calls[0].headers["idempotency-key"]
    expect(key).to match(/\A[0-9a-f-]{36}\z/)
    expect(http.calls[1].headers["idempotency-key"]).to eq(key)
    # Re-signed per attempt: same key, timestamp may differ but a signature is always present.
    expect(http.calls[1].headers["x-signature"]).to match(/\A[0-9a-f]{64}\z/)
  end

  it "honours a caller-supplied idempotency key and does not add one to read routes" do
    http = FakeHTTP.new([FakeHTTP.ok("uuid" => "u"), FakeHTTP.ok("uuid" => "u")])
    client = client_with(http)
    client.payouts.create(amount: "1", currency: "USDT", address: "T", order_id: "o",
                          idempotency_key: "my-key-1")
    client.payments.info("u")
    expect(http.calls[0].headers["idempotency-key"]).to eq("my-key-1")
    expect(http.calls[1].headers).not_to have_key("idempotency-key")
  end

  it "refuses an unusable caller key before anything is sent" do
    http = FakeHTTP.new([])
    expect do
      client_with(http).payments.create(amount: "1", currency: "USDT", idempotency_key: "with space")
    end.to raise_error(Oblodai::ValidationError, /printable ASCII/)
    expect(http.calls).to be_empty
  end

  it "does not retry a non-retryable error even on a 5xx" do
    http = FakeHTTP.new([FakeHTTP.api_error(500, { "code" => "internal", "retryable" => false })])
    expect { client_with(http).account.balance }
      .to raise_error(Oblodai::InternalError) { |e|
            expect(e.code).to eq("internal")
            expect(e.http_status).to eq(500)
            expect(e).not_to be_retryable
          }
    expect(http.calls.size).to eq(1)
  end

  it "retries a retryable error, honours Retry-After, and surfaces it after the budget" do
    limited = { "code" => "request.rate_limited", "retryable" => true, "retry_after" => 0 }
    http = FakeHTTP.new([
                          FakeHTTP.api_error(429, limited, "retry-after" => "0"),
                          FakeHTTP.api_error(429, limited),
                          FakeHTTP.api_error(429, limited)
                        ])
    error = nil
    begin
      client_with(http).account.balance
    rescue Oblodai::RateLimitError => e
      error = e
    end
    expect(error.retry_after).to eq(0)
    expect(http.calls.size).to eq(3) # 1 + max_retries(2)
  end

  it "retries a transport failure only when the request is safe to repeat" do
    boom = Oblodai::TransportError.new("transport.network", "network error: connection reset")

    read = FakeHTTP.new([{ raises: boom }, FakeHTTP.ok("balance" => { "merchant" => [] })])
    client_with(read).account.balance
    expect(read.calls.size).to eq(2)

    write = FakeHTTP.new([{ raises: boom }, FakeHTTP.ok({})])
    expect { client_with(write).settings.set_accuracy(enabled: true) }
      .to raise_error(Oblodai::TransportError) { |e| expect(e.code).to eq("transport.network") }
    expect(write.calls.size).to eq(1) # write without a key → never re-sent

    keyed = FakeHTTP.new([{ raises: boom }, FakeHTTP.ok("uuid" => "u")])
    client_with(keyed).payments.create(amount: "1", currency: "USDT")
    expect(keyed.calls.size).to eq(2) # keyed create → retried
  end

  it "classifies the error envelope into the right subclass and keeps request_id/field" do
    http = FakeHTTP.new([
                          FakeHTTP.api_error(400, { "code" => "payment.below_minimum", "message" => "too small",
                                                    "field" => "amount", "retryable" => false,
                                                    "request_id" => "rq-1" }),
                          FakeHTTP.api_error(401, { "code" => "merchant.bad_signature", "message" => "bad",
                                                    "retryable" => false }),
                          FakeHTTP.api_error(409, { "code" => "idempotency.key_reused", "message" => "reused",
                                                    "retryable" => false })
                        ])
    client = client_with(http, retry_policy: { max_retries: 0 })
    expect { client.payments.create(amount: "0", currency: "USDT") }
      .to raise_error(Oblodai::ValidationError) { |e|
            expect(e.code).to eq("payment.below_minimum")
            expect(e.field).to eq("amount")
            expect(e.request_id).to eq("rq-1")
            expect(e.family).to eq("payment")
          }
    expect { client.account.balance }.to raise_error(Oblodai::AuthenticationError)
    expect { client.payments.create(amount: "1", currency: "USDT") }
      .to raise_error(Oblodai::IdempotencyConflictError)
  end

  it "re-signs once with the server clock when a 401 reveals skew" do
    server_now = Time.now.to_i + 3600
    http = FakeHTTP.new([
                          FakeHTTP.api_error(401, { "code" => "merchant.bad_signature", "retryable" => false },
                                             "date" => Time.at(server_now).httpdate),
                          FakeHTTP.ok("balance" => { "merchant" => [] })
                        ])
    client_with(http, retry_policy: { max_retries: 0 }).account.balance
    expect(http.calls.size).to eq(2)
    expect(http.calls[1].headers["x-timestamp"].to_i).to be_within(5).of(server_now)
  end

  it "times out and reports transport.timeout" do
    http = FakeHTTP.new([{ delay_ms: 200, body: { "state" => 0, "result" => {} } }])
    expect { client_with(http, timeout_ms: 20, retry_policy: { max_retries: 0 }).account.balance }
      .to raise_error(Oblodai::TransportError) { |e| expect(e.code).to eq("transport.timeout") }
  end

  it "uses the payout credentials for payout routes when configured" do
    http = FakeHTTP.new([FakeHTTP.ok("uuid" => "p"), FakeHTTP.ok("uuid" => "i")])
    client = client_with(http, payout_public_id: "wk_test_1", payout_secret: "s2")
    client.payouts.create(amount: "1", currency: "USDT", address: "T", order_id: "o")
    client.payments.create(amount: "1", currency: "USDT")
    expect(http.calls[0].headers["x-public-id"]).to eq("wk_test_1")
    expect(http.calls[1].headers["x-public-id"]).to eq("pk_test_1")
  end

  it "retries batches.info with the payout key on merchant.wrong_key_kind" do
    http = FakeHTTP.new([
                          FakeHTTP.api_error(403, { "code" => "merchant.wrong_key_kind", "retryable" => false }),
                          FakeHTTP.ok("batch_id" => "b1", "kind" => "payout", "status" => "done")
                        ])
    client = client_with(http, payout_public_id: "wk_test_1", payout_secret: "s2")
    expect(client.batches.info("b1").batch_id).to eq("b1")
    expect(http.calls[0].headers["x-public-id"]).to eq("pk_test_1")
    expect(http.calls[1].headers["x-public-id"]).to eq("wk_test_1")
  end

  it "requires credentials only on the routes that need them" do
    http = FakeHTTP.new([FakeHTTP.ok("currencies" => [], "pricing_currencies" => [])])
    client = Oblodai::Client.new(base_url: "https://api.test", http: http)
    expect(client.catalog.currencies.currencies).to eq([])
    expect { client.account.balance }
      .to raise_error(Oblodai::ConfigError) { |e| expect(e.code).to eq("sdk.missing_credentials") }
  end

  it "sends the admin token on onboarding routes only" do
    http = FakeHTTP.new([FakeHTTP.ok("merchant_id" => "m1"), FakeHTTP.ok("balance" => { "merchant" => [] })])
    client = client_with(http, admin_token: "adm")
    client.merchants.create(email: "a@b.c", name: "A")
    client.account.balance
    expect(http.calls[0].headers["x-admin-token"]).to eq("adm")
    expect(http.calls[0].headers).not_to have_key("x-signature")
    expect(http.calls[1].headers).not_to have_key("x-admin-token")
  end
end
