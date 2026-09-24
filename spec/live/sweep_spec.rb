# frozen_string_literal: true

require_relative "live_helper"

# Live sweep: every namespace against a REAL core. The point is not the business outcome but that
# the bodies the SDK sends are accepted (no 400 from our own shapes) and the bodies that come back
# decode (no ContractError). Routes that need a subsystem the stand may lack (documents, email,
# static wallets) are probed and tolerated when the core reports them disabled.
RSpec.describe "live sweep", live: true do
  address = LiveHelper::ADDRESS

  before(:context) do
    @client, = LiveHelper.sandbox_client("sweep")
    @public = LiveHelper.public_client
    @client.sandbox.faucet(asset: "USDT", amount: "1000")
    # A per-invoice url_callback needs a registered endpoint (it signs with that endpoint's secret).
    @client.webhooks.register(url: LiveHelper::HOOK)
    @invoice = @client.payments.create(amount: "25", currency: "USDT", network: "tron",
                                       order_id: LiveHelper.unique("sw"), payer_email: "buyer@example.com",
                                       url_callback: LiveHelper::HOOK)
    @docs_enabled = begin
      @client.documents.get_balance
      true
    rescue Oblodai::NotFoundError => e
      e.code != "document.disabled"
    rescue Oblodai::Error
      false
    end
  end

  def unique(prefix) = LiveHelper.unique(prefix)

  it "catalog and account" do
    expect(@public.checkout.list_currencies.currencies).not_to be_empty
    expect(@public.account.list_exchange_rates(currency_from: "BTC")).not_to be_nil
    expect(@client.account.get_balance.balance.merchant).to be_an(Array)
    expect(@client.referrals.get_info.code).to be_a(String)
    expect([true, false]).to include(@client.settings.configure_vrcs.enabled)
    expect([true, false]).to include(@client.settings.configure_vrcs(enabled: false).enabled)
  end

  it "payments: lookups, qr, services, public checkout, batch, cancel, history" do
    expect(@client.payments.get_info(uuid: @invoice.uuid).uuid).to eq(@invoice.uuid)
    # Sandbox invoices carry a synthetic `sandbox:` address, which the core deliberately does not
    # render into a QR — the fields come back empty. A real invoice returns a data URI.
    expect(@client.payments.get_qr(uuid: @invoice.uuid).image).to be_a(String)
    expect(@client.payments.list_services(limit: 5).first_page.items).not_to be_empty
    expect(@public.checkout.get(@invoice.uuid).status).to eq("created")
    expect(@public.checkout.get_qr(@invoice.uuid).image).to be_a(String)

    multi = @client.payments.create(amount: "10", currency: "USDT", order_id: unique("sw-multi"))
    expect(@public.checkout.select_method(multi.uuid, currency: "USDT", network: "tron")).not_to be_nil

    LiveHelper.accept { @client.webhooks.resend_payment(uuid: @invoice.uuid) }
    LiveHelper.accept { @client.payments.send_email(uuid: @invoice.uuid) }

    job = @client.batches.create_payment(on_error: "continue",
                                         payments: [{ amount: "5", currency: "USDT", network: "tron",
                                                      order_id: unique("sw-b") }])
    expect(job).to be_a(Oblodai::Job)
    expect(@client.batches.get_info(batch_id: job.id).batch_id).to eq(job.id)

    to_cancel = @client.payments.create(amount: "5", currency: "USDT", network: "tron", order_id: unique("sw-c"))
    expect(@client.payments.cancel(uuid: to_cancel.uuid).status).to eq("cancelled")
    @client.payments.list_history(limit: 2).first(3).each { |p| expect(p.uuid).not_to be_empty }
  end

  it "deposit → paid → refund, resolve, refund batch" do
    @client.sandbox.simulate_deposit(invoice_id: @invoice.uuid, amount: "25", confirmations: 20,
                                     txid: unique("sw-tx"))
    expect(%w[paid confirm_check]).to include(@client.payments.get_info(uuid: @invoice.uuid).status)
    LiveHelper.accept do
      @client.refunds.payment(uuid: @invoice.uuid, address: address, amount: "5", reference: unique("sw-r"))
    end
    LiveHelper.accept { @client.payments.resolve(uuid: @invoice.uuid, action: "accept") }
    LiveHelper.accept do
      @client.batches.create_refund(refunds: [{ uuid: @invoice.uuid, address: address, amount: "5",
                                                reference: unique("sw-rb") }])
    end
  end

  it "payouts: calculate, validate, create, info, cancel, mass, batch, services, fee configs" do
    expect(@client.payouts.calculate(amount: "10", currency: "USDT", network: "tron").currency).to eq("USDT")
    expect(@client.payouts.validate(amount: "10", currency: "USDT", network: "tron", address: address).valid)
      .to be(true)

    payout = @client.payouts.create(amount: "10", currency: "USDT", network: "tron", address: address,
                                    order_id: unique("sw-po"))
    expect(@client.payouts.get_info(order_id: payout.order_id).uuid).to eq(payout.uuid)
    LiveHelper.accept { @client.payouts.cancel(uuid: payout.uuid) }
    LiveHelper.accept { @client.payouts.approve(uuid: payout.uuid) }

    mass = @client.payouts.create_mass(payouts: [{ amount: "5", currency: "USDT", network: "tron",
                                                   address: address, order_id: unique("sw-m") }])
    expect(mass.items.first.idx).to eq(0)

    job = @client.batches.create_payout(payouts: [{ amount: "5", currency: "USDT", network: "tron",
                                                    address: address, order_id: unique("sw-pb") }])
    expect(job.id).not_to be_empty
    expect(@client.payouts.list_services.first_page.items).not_to be_empty

    settings = @client.settings
    expect([true, false]).to include(settings.set_payout_fee_config(fee_on_recipient: true).fee_on_recipient)
    expect([true, false]).to include(settings.get_payout_fee_config.fee_on_recipient)
    expect([true, false]).to include(settings.set_refund_fee_config(fee_on_customer: true).fee_on_customer)
    expect([true, false]).to include(settings.get_refund_fee_config.fee_on_customer)
    expect(@client.payouts.list_history(kind: "refund", limit: 5).first_page.items).to be_an(Array)
  end

  it "payout links: create, get, list, claim preview/claim, cancel, batch" do
    link = @client.payout_links.create(amount: "5", currency: "USDT", network: "tron",
                                       reference: unique("sw-pl"), title: "Bonus", expires_in_seconds: 3600)
    expect(link.claim_token).not_to be_nil
    expect(@client.payout_links.get(link_id: link.link_id).status).to eq("funded")
    expect(@client.payout_links.list(limit: 5).first_page.items).not_to be_empty
    expect(@public.payout_links.get_payout_claim(link.claim_token).claimable).to be(true)
    expect(@public.payout_links.claim_payout(link.claim_token, address: address).payout_id).not_to be_empty

    second = @client.payout_links.create(amount: "5", currency: "USDT", network: "tron",
                                         reference: unique("sw-pl2"))
    expect(@client.payout_links.cancel(link_id: second.link_id).status).to eq("cancelled")

    batch = @client.payout_links.create_batch(items: [{ amount: "5", currency: "USDT", network: "tron",
                                                        reference: unique("sw-plb") }])
    expect(batch.items.first.ok).to be(true)
  end

  it "payment links: create, get, list, toggle, public view, checkout" do
    created = @client.payment_links.create(title: "Tip", amount_mode: "fixed", currency: "USDT",
                                           amount_fixed: "10", pinned_network: "tron")
    expect(created.link_id).not_to be_empty
    expect(@client.payment_links.get(link_id: created.link_id).active).to be(true)
    expect(@client.payment_links.list.first_page.items).not_to be_empty
    expect(@public.checkout.get_public_payment_link(created.link_id).amount_mode).to eq("fixed")
    expect(@public.checkout.payment_link(created.link_id, currency: "USDT", network: "tron")).not_to be_nil
    expect(@client.payment_links.toggle(link_id: created.link_id, active: false).active).to be(false)
  end

  it "splits and settings" do
    rule = @client.splits.create_rule(percent: "10", address: address, network: "tron", note: "partner")
    expect(@client.splits.list_rules.map(&:rule_id)).to include(rule.rule_id)
    expect(@client.splits.set_config(refund_hold_seconds: 3600).refund_hold_seconds).to eq(3600)
    expect(@client.splits.get_config.refund_hold_seconds).to eq(3600)
    expect(@client.splits.set_recipient_opt_in(enabled: true).enabled).to be(true)
    expect(@client.splits.get_recipient_opt_in.enabled).to be(true)
    expect(@client.splits.delete_rule(rule_id: rule.rule_id).ok).to be(true)

    settings = @client.settings
    expect(settings.set_discount(currency: "USDT", network: "tron", discount_percent: 2).discount_percent).to eq(2)
    expect(settings.list_discounts.first_page.items).not_to be_empty
    expect(settings.set_accuracy(enabled: true, accuracy_percent: 2).enabled).to be(true)
    expect(settings.get_accuracy.enabled).to be(true)
    expect(settings.set_auto_refund(overpay: true, underpay: false).overpay).to be(true)
    expect([true, false]).to include(settings.get_auto_refund.configured)
    expect(settings.set_accepted_currencies(accepted: [{ currency: "USDT", network: "tron" }]).ok).to be(true)
    expect(settings.list_accepted_currencies).not_to be_nil
    expect(settings.set_payment_fee_config(payer_pays_percent: 50).payer_pays_percent).to eq(50)
    expect(settings.get_payment_fee_config.payer_pays_percent).to eq(50)

    rules = settings.set_auto_withdraw_rule(currency: "USDT", network: "tron", address: address, min_amount: "100")
    expect(rules.items).not_to be_empty
    expect(settings.list_auto_withdraw_rules).not_to be_nil
    expect(settings.delete_auto_withdraw_rule(currency: "USDT")).not_to be_nil

    allowlist = @client.api_allowlist
    expect(allowlist.add_entry(cidr: "203.0.113.0/24").items).to include("203.0.113.0/24")
    expect(allowlist.list.items).to include("203.0.113.0/24")
    expect(allowlist.set_enabled(enabled: false).enabled).to be(false)
    expect(allowlist.remove_entry(cidr: "203.0.113.0/24").items).not_to include("203.0.113.0/24")
  end

  it "webhooks and the sandbox inspector" do
    endpoint = @client.webhooks.register(url: LiveHelper::HOOK)
    expect(endpoint.endpoint_id).not_to be_empty
    expect(@client.webhooks.rotate_secret.secret).not_to be_empty
    expect(@client.webhooks.list_deliveries(limit: 5).first_page.items).to be_an(Array)
    LiveHelper.accept do
      @client.webhooks.send_test_payment(url_callback: LiveHelper::HOOK, currency: "USDT", network: "tron",
                                         status: "paid")
    end
    LiveHelper.accept { @client.webhooks.send_legacy_test(url: LiveHelper::HOOK, status: "paid") }

    inspector = @client.sandbox.list_webhooks(limit: 5).first_page
    expect(inspector.items).to be_an(Array)
    terminal = inspector.items.find { |d| %w[delivered dead].include?(d.status) }
    LiveHelper.accept { @client.sandbox.replay_webhook(delivery_id: terminal.id) } if terminal
  end

  it "wallets and transfers (refused for a dev store, as documented)" do
    LiveHelper.accept { @client.wallets.create(currency: "USDT", network: "tron", order_id: unique("sw-w")) }
    LiveHelper.accept { @client.wallets.get_qr(address: address) }
    LiveHelper.accept { @client.wallets.block(address: address) }
    LiveHelper.accept { @client.refunds.blocked_wallet(uuid: SecureRandom.uuid, address: address) }
    LiveHelper.accept { @client.payouts.transfer_to_personal(amount: "5", currency: "USDT") }
    recipient = SecureRandom.uuid # a platform user id that does not exist: a 404, not a shape error
    LiveHelper.accept { @client.payouts.transfer_to_user(to_user_id: recipient, amount: "5", currency: "USDT") }
  end

  it "documents (when the stand has a renderer)" do
    skip "the stand reports documents disabled" unless @docs_enabled

    statement = @client.documents.get_statement(from: "2026-01-01", to: "2026-12-31", lang: "en")
    expect(statement.content_type).to match(/pdf/)
    expect(statement.size).to be > 0
    expect(@client.documents.get_fees.size).to be > 0
    expect(@client.documents.get_ledger(format_: "csv").content_type).to match(/csv|pdf/)
    LiveHelper.accept { @client.documents.get_referrals(lang: "en") }

    job = @client.documents.create_job(kind: "statement", format_: "csv", lang: "en",
                                       from: "2026-01-01", to: "2026-12-31")
    expect(@client.documents.get_job(job_id: job.id).job_id).to eq(job.id)
    LiveHelper.accept { job.download }

    info = @client.payments.get_info(uuid: @invoice.uuid)
    uri = URI.parse(info.document_url)
    kind, id = uri.path.split("/")[3, 2]
    query = URI.decode_www_form(uri.query.to_s).to_h
    document = @public.documents.get_signed(kind, id, exp: query["exp"], sig: query["sig"])
    expect(document.content_type).to match(/pdf/)
  end

  it "sandbox reset last" do
    expect(@client.sandbox.reset.invoices_cancelled).to be_a(Integer)
  end
end
