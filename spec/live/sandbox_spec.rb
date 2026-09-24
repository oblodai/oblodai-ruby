# frozen_string_literal: true

require_relative "live_helper"

RSpec.describe "live sandbox journey", live: true do
  before(:context) do
    @client, = LiveHelper.sandbox_client("live")
  end

  it "reads public catalog data without credentials" do
    currencies = LiveHelper.public_client.checkout.list_currencies
    expect(currencies.currencies).not_to be_empty
  end

  it "creates an invoice and reads it back by order_id and uuid (signed GET with query too)" do
    invoice = @client.payments.create(amount: "25", currency: "USDT", network: "tron",
                                      order_id: LiveHelper.unique("sdk-live"))
    expect(invoice.status).to eq("created")
    expect(invoice.amount).to be_a(BigDecimal)

    expect(@client.payments.get_info(order_id: invoice.order_id).uuid).to eq(invoice.uuid)
    page = @client.payments.list_history(limit: 5).first_page
    expect(page.items.map(&:uuid)).to include(invoice.uuid)
    expect(page.total).to be >= 1

    hooks = @client.sandbox.list_webhooks(limit: 5, offset: 0).first_page # GET signed over path+query
    expect(hooks.items).to be_an(Array)
  end

  it "replays an idempotent create and refuses a reused key with a different body" do
    key = LiveHelper.unique("sdk-idem")
    body = { "amount" => "5", "currency" => "USDT", "network" => "tron", "order_id" => "#{key}-o" }
    first = @client.payments.create(body, idempotency_key: key)
    second = @client.payments.create(body, idempotency_key: key)
    expect(second.uuid).to eq(first.uuid)

    expect do
      @client.payments.create(body.merge("amount" => "2", "order_id" => "#{key}-o2"), idempotency_key: key)
    end.to raise_error(Oblodai::IdempotencyConflictError) { |e|
      expect(e.code).to eq("idempotency.key_reused")
      expect(e.http_status).to eq(409)
    }
  end

  it "simulates a deposit, sees the invoice paid, and funds/validates/creates a payout" do
    invoice = @client.payments.create(amount: "25", currency: "USDT", network: "tron",
                                      order_id: LiveHelper.unique("sdk-pay"))
    @client.sandbox.simulate_deposit(invoice_id: invoice.uuid, amount: "25", confirmations: 20,
                                     txid: LiveHelper.unique("sdk-tx"))
    paid = @client.payments.get_info(uuid: invoice.uuid)
    expect(Oblodai::Status.payment_paid?(paid.status)).to be(true)

    @client.sandbox.faucet(asset: "USDT", amount: "100")
    usdt = @client.account.get_balance.balance.merchant.find { |entry| entry.currency == "USDT" }
    expect(Oblodai::Money.compare(usdt.balance, "0")).to eq(1)

    calculation = @client.payouts.calculate(amount: "10", currency: "USDT", network: "tron")
    expect(calculation.fee_bearer).not_to be_nil
    validation = @client.payouts.validate(amount: "10", currency: "USDT", network: "tron",
                                          address: LiveHelper::ADDRESS)
    expect(validation.valid).to be(true)

    payout = @client.payouts.create(amount: BigDecimal("10"), currency: "USDT", network: "tron",
                                    address: LiveHelper::ADDRESS, order_id: LiveHelper.unique("sdk-po"))
    expect(payout.uuid).not_to be_empty
    expect(@client.payouts.get_info(uuid: payout.uuid).order_id).to eq(payout.order_id)
  end

  it "classifies a domain refusal with the core's own retryable flag" do
    expect do
      @client.payouts.create(amount: "999999", currency: "USDT", network: "tron",
                             address: LiveHelper::ADDRESS, order_id: LiveHelper.unique("sdk-big"))
    end.to raise_error(Oblodai::Error) { |e|
      expect(e.code).to eq("payout.insufficient_funds")
      expect(e.http_status).to eq(409)
      expect(e.request_id).to be_a(String)
      expect(e.message).to include("[payout.insufficient_funds]", "request_id=")
    }
  end

  it "registers a webhook endpoint and rehearses a delivery the core signs" do
    endpoint = @client.webhooks.register(url: LiveHelper::HOOK)
    expect(endpoint.endpoint_id).not_to be_empty
    secret = endpoint.secret || @client.webhooks.rotate_secret.secret
    expect(secret).not_to be_empty
    LiveHelper.accept do
      @client.webhooks.send_test_payment(url_callback: LiveHelper::HOOK, currency: "USDT", network: "tron",
                                         status: "paid")
    end
  end
end
