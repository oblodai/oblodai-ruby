# frozen_string_literal: true

# Every route the core declares has exactly one SDK method, wired to the right METHOD and path,
# signed with the right key kind and carrying an Idempotency-Key exactly where the core
# deduplicates. The table below is the SDK's coverage ledger: a new core route fails this spec
# until a method is added for it.
ANY_RESULT = { "state" => 0,
               "result" => { "items" => [], "enabled" => true,
                             "paginate" => { "total" => 0, "per_page" => 1, "offset" => 0,
                                             "has_pages" => false } } }.freeze

COVERAGE = {
  "GET /v1/claim/{token}" => ->(c) { c.payout_links.claim_preview("tok") },
  "GET /v1/currencies" => ->(c) { c.catalog.currencies },
  "GET /v1/documents/balance" => ->(c) { c.documents.balance_certificate },
  "GET /v1/documents/batch" => ->(c) { c.documents.batch_report("b1") },
  "GET /v1/documents/fees" => ->(c) { c.documents.fee_schedule },
  "GET /v1/documents/jobs/file" => ->(c) { c.documents.job_file("j1") },
  "GET /v1/documents/ledger" => ->(c) { c.documents.ledger },
  "GET /v1/documents/link" => ->(c) { c.documents.link_report("l1") },
  "GET /v1/documents/referrals" => ->(c) { c.documents.referrals_report },
  "GET /v1/documents/split" => ->(c) { c.documents.split_report("i1") },
  "GET /v1/documents/statement" => ->(c) { c.documents.statement(from: "2026-01-01", to: "2026-02-01") },
  "GET /v1/documents/wallet/statement" => ->(c) { c.documents.wallet_statement("w1") },
  "GET /v1/documents/{kind}/{id}" => ->(c) { c.documents.download("invoice", "i1", exp: 1, sig: "s") },
  "GET /v1/link/{id}" => ->(c) { c.payment_links.public_view("l1") },
  "GET /v1/pay/{id}" => ->(c) { c.payments.public_view("i1") },
  "GET /v1/pay/{id}/qr" => ->(c) { c.payments.public_qr("i1") },
  "GET /v1/sandbox/webhooks" => ->(c) { c.sandbox.webhooks.first_page },
  "POST /v1/api-allowlist/add" => ->(c) { c.settings.add_api_allowlist("10.0.0.0/8") },
  "POST /v1/api-allowlist/enable" => ->(c) { c.settings.enable_api_allowlist(true) },
  "POST /v1/api-allowlist/list" => ->(c) { c.settings.list_api_allowlist },
  "POST /v1/api-allowlist/remove" => ->(c) { c.settings.remove_api_allowlist("10.0.0.0/8") },
  "POST /v1/auto-withdraw/delete" => ->(c) { c.settings.delete_auto_withdraw("USDT") },
  "POST /v1/auto-withdraw/list" => ->(c) { c.settings.list_auto_withdraw },
  "POST /v1/auto-withdraw/set" => lambda { |c|
    c.settings.set_auto_withdraw(currency: "USDT", network: "tron", address: "T")
  },
  "POST /v1/balance" => ->(c) { c.account.balance },
  "POST /v1/batch/info" => ->(c) { c.batches.info("b1") },
  "POST /v1/claim/{token}" => ->(c) { c.payout_links.claim("tok", address: "T") },
  "POST /v1/exchange-rate/list" => ->(c) { c.catalog.exchange_rates.first_page },
  "POST /v1/link/{id}/checkout" => ->(c) { c.payment_links.checkout("l1") },
  "POST /v1/pay/{id}/select" => ->(c) { c.payments.select("i1", currency: "USDT", network: "tron") },
  "POST /v1/payment" => ->(c) { c.payments.create(amount: "1", currency: "USDT") },
  "POST /v1/payment/accepted/list" => ->(c) { c.settings.list_accepted.first_page },
  "POST /v1/payment/accepted/set" => ->(c) { c.settings.set_accepted(accepted: []) },
  "POST /v1/payment/accuracy/get" => ->(c) { c.settings.get_accuracy },
  "POST /v1/payment/accuracy/set" => ->(c) { c.settings.set_accuracy(enabled: true) },
  "POST /v1/payment/autorefund/get" => ->(c) { c.settings.get_auto_refund },
  "POST /v1/payment/autorefund/set" => ->(c) { c.settings.set_auto_refund(overpay: true, underpay: false) },
  "POST /v1/payment/batch" => ->(c) { c.payments.batch(payments: []) },
  "POST /v1/payment/cancel" => ->(c) { c.payments.cancel("i1") },
  "POST /v1/payment/discount/list" => ->(c) { c.settings.list_discounts.first_page },
  "POST /v1/payment/discount/set" => ->(c) { c.settings.set_discount(discount_percent: 1) },
  "POST /v1/payment/fee-config/get" => ->(c) { c.settings.get_payment_fee_config },
  "POST /v1/payment/fee-config/set" => ->(c) { c.settings.set_payment_fee_config(payer_pays_percent: 50) },
  "POST /v1/payment/history" => ->(c) { c.payments.history.first_page },
  "POST /v1/payment/info" => ->(c) { c.payments.info("i1") },
  "POST /v1/payment/link" => ->(c) { c.payment_links.create(amount_mode: "open", currency: "USDT") },
  "POST /v1/payment/link/info" => ->(c) { c.payment_links.info("l1") },
  "POST /v1/payment/link/list" => ->(c) { c.payment_links.list.first_page },
  "POST /v1/payment/link/toggle" => ->(c) { c.payment_links.toggle("l1", false) },
  "POST /v1/payment/qr" => ->(c) { c.payments.qr("i1") },
  "POST /v1/payment/refund" => ->(c) { c.refunds.create(uuid: "i1") },
  "POST /v1/payment/resend" => ->(c) { c.payments.resend("i1") },
  "POST /v1/payment/resolve" => ->(c) { c.refunds.resolve(uuid: "i1", action: "accept") },
  "POST /v1/payment/send-email" => ->(c) { c.payments.send_email(uuid: "i1") },
  "POST /v1/payment/services" => ->(c) { c.payments.services.first_page },
  "POST /v1/payment/testing-webhook" => ->(c) { c.webhooks.test_legacy(url: "https://x") },
  "POST /v1/payout" => lambda { |c|
    c.payouts.create(amount: "1", currency: "USDT", address: "T", order_id: "o")
  },
  "POST /v1/payout/approve" => ->(c) { c.payouts.approve("p1") },
  "POST /v1/payout/batch" => ->(c) { c.payouts.batch(payouts: []) },
  "POST /v1/payout/calculate" => ->(c) { c.payouts.calculate(amount: "1", currency: "USDT") },
  "POST /v1/payout/cancel" => ->(c) { c.payouts.cancel("p1") },
  "POST /v1/payout/fee-config/get" => ->(c) { c.payouts.get_fee_config },
  "POST /v1/payout/fee-config/set" => ->(c) { c.payouts.set_fee_config(fee_on_recipient: true) },
  "POST /v1/payout/history" => ->(c) { c.payouts.history.first_page },
  "POST /v1/payout/info" => ->(c) { c.payouts.info("p1") },
  "POST /v1/payout/link" => lambda { |c|
    c.payout_links.create(amount: "1", currency: "USDT", network: "tron")
  },
  "POST /v1/payout/link/batch" => ->(c) { c.payout_links.batch(items: []) },
  "POST /v1/payout/link/cancel" => ->(c) { c.payout_links.cancel("l1") },
  "POST /v1/payout/link/cheque" => ->(c) { c.payout_links.cheque(claim_token: "t") },
  "POST /v1/payout/link/info" => ->(c) { c.payout_links.info("l1") },
  "POST /v1/payout/link/list" => ->(c) { c.payout_links.list.first_page },
  "POST /v1/payout/mass" => ->(c) { c.payouts.mass(payouts: []) },
  "POST /v1/payout/refund-fee-config/get" => ->(c) { c.payouts.get_refund_fee_config },
  "POST /v1/payout/refund-fee-config/set" => ->(c) { c.payouts.set_refund_fee_config(fee_on_customer: true) },
  "POST /v1/payout/services" => ->(c) { c.payouts.services.first_page },
  "POST /v1/payout/validate" => lambda { |c|
    c.payouts.validate(amount: "1", currency: "USDT", address: "T")
  },
  "POST /v1/referral/info" => ->(c) { c.account.referral },
  "POST /v1/refund/batch" => ->(c) { c.refunds.batch(refunds: []) },
  "POST /v1/sandbox/deposit" => ->(c) { c.sandbox.deposit(invoice_id: "i1") },
  "POST /v1/sandbox/faucet" => ->(c) { c.sandbox.faucet(asset: "USDT", amount: "1") },
  "POST /v1/sandbox/reset" => ->(c) { c.sandbox.reset },
  "POST /v1/sandbox/webhooks/replay" => ->(c) { c.sandbox.replay("d1") },
  "POST /v1/split/config/get" => ->(c) { c.splits.get_config },
  "POST /v1/split/config/set" => ->(c) { c.splits.set_config(refund_hold_seconds: 60) },
  "POST /v1/split/recipient/optin" => ->(c) { c.splits.set_opt_in(true) },
  "POST /v1/split/recipient/optin/get" => ->(c) { c.splits.get_opt_in },
  "POST /v1/split/rule" => ->(c) { c.splits.create_rule(percent: "10") },
  "POST /v1/split/rule/delete" => ->(c) { c.splits.delete_rule("r1") },
  "POST /v1/split/rule/list" => ->(c) { c.splits.list_rules.first_page },
  "POST /v1/test-webhook/payment" => ->(c) { c.webhooks.test("payment", url_callback: "https://x") },
  "POST /v1/test-webhook/payout" => ->(c) { c.webhooks.test("payout", url_callback: "https://x") },
  "POST /v1/test-webhook/wallet" => ->(c) { c.webhooks.test("wallet", url_callback: "https://x") },
  "POST /v1/transfer/batch" => ->(c) { c.transfers.batch(transfers: []) },
  "POST /v1/transfer/to-personal" => ->(c) { c.transfers.to_personal(amount: "1", currency: "USDT") },
  "POST /v1/transfer/to-user" => lambda { |c|
    c.transfers.to_user(to_user_id: "u", amount: "1", currency: "USDT")
  },
  "POST /v1/vrcs" => ->(c) { c.account.vrcs },
  "POST /v1/wallet" => ->(c) { c.wallets.create(currency: "USDT", network: "tron") },
  "POST /v1/wallet/block" => ->(c) { c.wallets.block(address: "T") },
  "POST /v1/wallet/blocked-address-refund" => ->(c) { c.wallets.refund_blocked_deposit(uuid: "w1", address: "T") },
  "POST /v1/wallet/qr" => ->(c) { c.wallets.qr("T") },
  "POST /v1/webhooks" => ->(c) { c.webhooks.register("https://x") },
  "POST /v1/webhooks/deliveries" => ->(c) { c.webhooks.deliveries.first_page },
  "POST /v1/webhooks/rotate-secret" => ->(c) { c.webhooks.rotate_secret },
  "POST /v1/documents/jobs" => ->(c) { c.documents.create_job(kind: "statement") },
  "POST /v1/documents/jobs/info" => ->(c) { c.documents.job_info("j1") },
  "POST /v1/merchants" => ->(c) { c.merchants.create(email: "a@b.c", name: "A") },
  "POST /v1/merchants/{id}/sandbox" => ->(c) { c.merchants.create_sandbox("m1") }
}.freeze

RSpec.describe "route coverage" do
  it "is the core's merchant surface, nothing more and nothing less" do
    expect(Oblodai::Contract::ROUTES.keys.sort).to eq(Fixtures.declared_routes.sort)
    expect(Oblodai::Contract::ROUTES.size).to eq(107)
  end

  it "has one SDK method per route" do
    expect(COVERAGE.keys.sort).to eq(Oblodai::Contract::ROUTES.keys.sort)
  end

  it "every recorded fixture belongs to a known route" do
    Fixtures.fixtures.each_key { |route| expect(Oblodai::Contract::ROUTES).to have_key(route) }
  end

  Oblodai::Contract::ROUTES.each do |key, spec|
    it "#{key} is wired to the right method, path, key kind and idempotency" do
      http = FakeHTTP.new([
                            if spec.bare
                              { status: 200, body: "%PDF", headers: { "content-type" => "application/pdf" } }
                            else
                              { status: 200, body: ANY_RESULT }
                            end
                          ])
      client = Oblodai::Client.new(public_id: "pk", secret: "s", payout_public_id: "wk",
                                   payout_secret: "s2", admin_token: "adm",
                                   base_url: "https://api.test", http: http)
      COVERAGE.fetch(key).call(client)

      expect(http.calls.size).to eq(1)
      call = http.calls.first
      expect(call.verb).to eq(spec.method)
      expect(call.path).to match(/\A#{spec.path.gsub(/\{[a-z_]+\}/, "[^/]+")}\z/)

      case spec.auth
      when :public
        expect(call.headers).not_to have_key("x-signature")
      when :onboard
        expect(call.headers).not_to have_key("x-signature")
        expect(call.headers["x-admin-token"]).to eq("adm")
      else
        expect(call.headers["x-public-id"]).to eq(spec.auth == :payout ? "wk" : "pk")
        expect(call.headers["x-signature"]).to match(/\A[0-9a-f]{64}\z/)
      end

      if spec.idempotent
        expect(call.headers["idempotency-key"]).to match(/\A[0-9a-f-]{36}\z/)
      else
        expect(call.headers).not_to have_key("idempotency-key")
      end
    end
  end
end
