# frozen_string_literal: true

RSpec.describe Oblodai::Transport do
  let(:balance) { FakeHTTP.ok_for("getBalance") }

  it "signs path+query on GET and sends no body" do
    http = FakeHTTP.new([FakeHTTP.ok_for("sandboxListWebhooks")])
    client_with(http).sandbox.list_webhooks(limit: 10, offset: 0).first_page
    call = http.calls.first
    expect(call.url).to eq("https://api.test/v1/sandbox/webhooks?limit=10&offset=0")
    expect(call.body).to be_nil
    expect(call.headers[SIGNING::HEADER_PUBLIC_ID.downcase]).to eq("pk_test_1")
    expect(call.headers[SIGNING::HEADER_SIGNATURE.downcase]).to match(/\A[0-9a-f]{64}\z/)
    expect(call.headers[SIGNING::HEADER_TIMESTAMP.downcase].to_i).to be_within(5).of(Time.now.to_i)
  end

  it "generates one Idempotency-Key per create call and reuses it across retries" do
    http = FakeHTTP.new([
                          FakeHTTP.api_error(503, { "code" => "db.unavailable", "message" => "down",
                                                    "retryable" => true }),
                          FakeHTTP.ok_for("createPayment")
                        ])
    client_with(http).payments.create(amount: "1", currency: "USDT")
    expect(http.calls.size).to eq(2)
    key = http.calls[0].headers[SIGNING::HEADER_IDEMPOTENCY_KEY.downcase]
    expect(key).to match(/\A[0-9a-f-]{36}\z/)
    expect(http.calls[1].headers[SIGNING::HEADER_IDEMPOTENCY_KEY.downcase]).to eq(key)
    # Re-signed per attempt: same key, timestamp may differ but a signature is always present.
    expect(http.calls[1].headers[SIGNING::HEADER_SIGNATURE.downcase]).to match(/\A[0-9a-f]{64}\z/)
  end

  it "honours a caller-supplied idempotency key and does not add one to read routes" do
    http = FakeHTTP.new([FakeHTTP.ok_for("createPayout"), FakeHTTP.ok_for("getPaymentInfo")])
    client = client_with(http)
    client.payouts.create(amount: "1", currency: "USDT", address: "T", order_id: "o",
                          idempotency_key: "my-key-1")
    client.payments.get_info(uuid: "u")
    expect(http.calls[0].headers[SIGNING::HEADER_IDEMPOTENCY_KEY.downcase]).to eq("my-key-1")
    expect(http.calls[1].headers).not_to have_key(SIGNING::HEADER_IDEMPOTENCY_KEY.downcase)
  end

  it "refuses an unusable caller key before anything is sent" do
    http = FakeHTTP.new([])
    expect do
      client_with(http).payments.create(amount: "1", currency: "USDT", idempotency_key: "with space")
    end.to raise_error(Oblodai::ConfigError, /printable ASCII/)
    expect(http.calls).to be_empty
  end

  it "does not retry a non-retryable error even on a 5xx" do
    http = FakeHTTP.new([FakeHTTP.api_error(500, { "code" => "internal", "retryable" => false })])
    expect { client_with(http).account.get_balance }
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
      client_with(http).account.get_balance
    rescue Oblodai::RateLimitError => e
      error = e
    end
    expect(error.retry_after).to eq(0)
    expect(http.calls.size).to eq(3) # 1 + max_retries(2)
  end

  it "retries a transport failure only when the request is safe to repeat" do
    boom = Oblodai::TransportError.new("transport.network", "network error: connection reset")

    read = FakeHTTP.new([{ raises: boom }, balance])
    client_with(read).account.get_balance
    expect(read.calls.size).to eq(2)

    write = FakeHTTP.new([{ raises: boom }, FakeHTTP.ok_for("setAccuracy")])
    expect { client_with(write).settings.set_accuracy(enabled: true) }
      .to raise_error(Oblodai::TransportError) { |e| expect(e.code).to eq("transport.network") }
    expect(write.calls.size).to eq(1) # write without a key → never re-sent

    keyed = FakeHTTP.new([{ raises: boom }, FakeHTTP.ok_for("createPayment")])
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
    expect { client.account.get_balance }.to raise_error(Oblodai::AuthenticationError)
    expect { client.payments.create(amount: "1", currency: "USDT") }
      .to raise_error(Oblodai::IdempotencyConflictError)
  end

  it "re-signs once with the server clock when a 401 reveals skew" do
    server_now = Time.now.to_i + 3600
    http = FakeHTTP.new([
                          FakeHTTP.api_error(401, { "code" => "merchant.bad_signature", "retryable" => false },
                                             "date" => Time.at(server_now).httpdate),
                          balance
                        ])
    client_with(http, retry_policy: { max_retries: 0 }).account.get_balance
    expect(http.calls.size).to eq(2)
    expect(http.calls[1].headers[SIGNING::HEADER_TIMESTAMP.downcase].to_i).to be_within(5).of(server_now)
  end

  it "times out and reports transport.timeout" do
    http = FakeHTTP.new([{ delay: 0.2, body: { "state" => 0, "result" => {} } }])
    expect { client_with(http, timeout: 0.02, retry_policy: { max_retries: 0 }).account.get_balance }
      .to raise_error(Oblodai::TransportError) { |e| expect(e.code).to eq("transport.timeout") }
  end

  it "hands the adapter the per-attempt timeout in seconds, capped by the call deadline" do
    http = FakeHTTP.new([balance, balance, balance])
    client = client_with(http, timeout: 7, deadline: 60)
    client.account.get_balance
    client.account.get_balance(timeout: 2.5)
    client_with(http, timeout: 30, deadline: 3).account.get_balance
    expect(http.calls[0].timeout).to eq(7.0)
    expect(http.calls[1].timeout).to eq(2.5)
    expect(http.calls[2].timeout).to be <= 3.0
  end

  it "signs a payout, an invoice and a batch lookup with the one API key" do
    http = FakeHTTP.new([FakeHTTP.ok_for("createPayout"), FakeHTTP.ok_for("createPayment"),
                         FakeHTTP.ok_for("getBatchInfo")])
    client = client_with(http)
    client.payouts.create(amount: "1", currency: "USDT", address: "T", order_id: "o")
    client.payments.create(amount: "1", currency: "USDT")
    client.batches.get_info(batch_id: "b1")
    expect(http.calls.map { |call| call.headers[SIGNING::HEADER_PUBLIC_ID.downcase] }).to eq(["pk_test_1"] * 3)
    expect(http.calls.map { |call| call.headers[SIGNING::HEADER_SIGNATURE.downcase] }).to all(match(/\A[0-9a-f]{64}\z/))
  end

  it "takes no per-call key preference: there is no second key to prefer" do
    http = FakeHTTP.new([])
    expect { client_with(http).payouts.get_info(uuid: "p1", prefer_payout_key: true) }
      .to raise_error(ArgumentError, /prefer_payout_key/)
    expect(http.calls).to be_empty
  end

  it "requires credentials only on the routes that need them" do
    http = FakeHTTP.new([FakeHTTP.ok_for("listCurrencies", "currencies" => [])])
    client = Oblodai::Client.new(base_url: "https://api.test", http: http)
    expect(client.checkout.list_currencies.currencies).to eq([])
    expect { client.account.get_balance }
      .to raise_error(Oblodai::ConfigError) { |e| expect(e.code).to eq("sdk.missing_credentials") }
  end

  it "sends the admin token on onboarding routes only" do
    http = FakeHTTP.new([FakeHTTP.ok_for("onboardSandboxStore"), balance])
    client = client_with(http, admin_token: "adm")
    client.sandbox.onboard_store("m1")
    client.account.get_balance
    expect(http.calls[0].headers["x-admin-token"]).to eq("adm")
    expect(http.calls[0].headers).not_to have_key(SIGNING::HEADER_SIGNATURE.downcase)
    expect(http.calls[1].headers).not_to have_key("x-admin-token")
  end
end
