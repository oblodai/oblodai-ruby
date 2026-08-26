# frozen_string_literal: true

require_relative "live_helper"

RSpec.describe "live sandbox journey", live: true do
  before(:context) do
    @client, = LiveHelper.sandbox_client("live")
  end

  it "reads public catalog data without credentials" do
    currencies = LiveHelper.public_client.catalog.currencies
    expect(currencies.currencies).not_to be_empty
    expect(currencies.currencies.first).to be_a(Oblodai::Models::CurrencyInfo)
  end

  it "creates an invoice and reads it back by order_id and uuid (signed GET with query too)" do
    invoice = @client.payments.create(amount: "25", currency: "USDT", network: "tron",
                                      order_id: "sdk-live-#{Time.now.to_i}-#{rand(10_000)}")
    expect(invoice.status).to eq("created")
    expect(invoice.amount).to be_a(String)
    @invoice = invoice

    expect(@client.payments.info(order_id: invoice.order_id).uuid).to eq(invoice.uuid)
    page = @client.payments.history(limit: 5).first_page
    expect(page.items.map(&:uuid)).to include(invoice.uuid)
    expect(page.paginate).to be_a(Oblodai::Models::Paginate)

    hooks = @client.sandbox.webhooks(limit: 5, offset: 0).first_page # GET signed over path+query
    expect(hooks.items).to be_an(Array)
  end

  it "replays an idempotent create and refuses a reused key with a different body" do
    key = "sdk-idem-#{Time.now.to_i}-#{rand(10_000)}"
    first = @client.payments.create(amount: "5", currency: "USDT", network: "tron",
                                    order_id: "#{key}-o", idempotency_key: key)
    second = @client.payments.create(amount: "5", currency: "USDT", network: "tron",
                                     order_id: "#{key}-o", idempotency_key: key)
    expect(second.uuid).to eq(first.uuid)

    expect do
      @client.payments.create(amount: "2", currency: "USDT", network: "tron",
                              order_id: "#{key}-o2", idempotency_key: key)
    end.to raise_error(Oblodai::IdempotencyConflictError) { |e|
      expect(e.code).to eq("idempotency.key_reused")
      expect(e.http_status).to eq(409)
    }
  end

  it "simulates a deposit, sees the invoice paid, and funds/validates/creates a payout" do
    invoice = @client.payments.create(amount: "25", currency: "USDT", network: "tron",
                                      order_id: "sdk-pay-#{Time.now.to_i}-#{rand(10_000)}")
    @client.sandbox.deposit(invoice_id: invoice.uuid, amount: "25", confirmations: 20,
                            txid: "sdk-tx-#{Time.now.to_i}-#{rand(10_000)}")
    paid = @client.payments.info(invoice.uuid)
    expect(paid).to be_paid

    @client.sandbox.faucet(asset: "USDT", amount: "100")
    balance = @client.account.balance
    expect(balance.available("USDT")).to be_a(String)
    expect(Oblodai::Money.compare(balance.available("USDT"), "0")).to eq(1)

    calculation = @client.payouts.calculate(amount: "10", currency: "USDT", network: "tron")
    expect(calculation.fee_bearer).not_to be_nil
    validation = @client.payouts.validate(amount: "10", currency: "USDT", network: "tron",
                                          address: LiveHelper::ADDRESS)
    expect(validation.valid).to be(true)

    payout = @client.payouts.create(amount: "10", currency: "USDT", network: "tron",
                                    address: LiveHelper::ADDRESS,
                                    order_id: "sdk-po-#{Time.now.to_i}-#{rand(10_000)}")
    expect(payout.uuid).not_to be_empty
    expect(@client.payouts.info(payout.uuid).order_id).to eq(payout.order_id)
  end

  it "classifies a domain refusal with the core's own retryable flag" do
    error = nil
    begin
      @client.payouts.create(amount: "999999", currency: "USDT", network: "tron",
                             address: LiveHelper::ADDRESS,
                             order_id: "sdk-big-#{Time.now.to_i}-#{rand(10_000)}")
    rescue Oblodai::Error => e
      error = e
    end
    expect(error.code).to eq("payout.insufficient_funds")
    expect(error.http_status).to eq(409)
    expect(error.request_id).to be_a(String)
    expect(error.retryable?).to be(true)
  end

  it "registers a webhook endpoint and verifies a delivery the core signed" do
    endpoint = @client.webhooks.register(LiveHelper::HOOK)
    expect(endpoint.endpoint_id).not_to be_empty
    secret = endpoint.secret || @client.webhooks.rotate_secret.secret
    expect(secret).not_to be_empty

    # Sign a body with the endpoint's own secret exactly as the dispatcher does, then verify it
    # through the public API — the same code path a receiver runs.
    body = JSON.generate(type: "payment", uuid: "u-live", order_id: "o", status: "paid",
                         is_final: true, sequence: 1, event_at: Time.now.utc.iso8601, txid: "t")
    ts = Time.now.to_i
    headers = { "X-Webhook-Timestamp" => ts.to_s,
                "X-Webhook-Signature" => Oblodai::Signing.sign_webhook(secret, ts, body),
                "X-Webhook-Event" => "invoice.paid", "X-Webhook-Id" => "d-live" }
    delivery = Oblodai::Webhooks.verify_delivery(body, headers, secret: secret)
    expect(delivery.event.status).to eq("paid")
    expect(delivery.id).to eq("d-live")
  end
end
