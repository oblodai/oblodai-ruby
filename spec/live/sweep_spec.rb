# frozen_string_literal: true

require_relative "live_helper"

# Live sweep: every namespace against a REAL core. The point is not the business outcome but that
# the bodies the SDK sends are accepted (no 400 from our own shapes) and the bodies that come back
# decode (no ContractError). Routes that need a subsystem the stand may lack (documents, email) are
# probed and skipped when the core reports them disabled.
RSpec.describe "live sweep", live: true do
  before(:context) do
    @client, = LiveHelper.sandbox_client("sweep")
    @public = LiveHelper.public_client
    @client.sandbox.faucet(asset: "USDT", amount: "1000")
    # A per-invoice url_callback needs a registered endpoint (it signs with that endpoint's secret).
    @client.webhooks.register(LiveHelper::HOOK)
    @invoice = @client.payments.create(amount: "25", currency: "USDT", network: "tron",
                                       order_id: "sw-#{Time.now.to_i}-#{rand(10_000)}",
                                       payer_email: "buyer@example.com",
                                       url_callback: LiveHelper::HOOK)
    @docs_enabled = begin
      @client.documents.balance_certificate
      true
    rescue Oblodai::NotFoundError => e
      e.code != "document.disabled"
    rescue Oblodai::Error
      false
    end
  end

  def unique(prefix)
    "#{prefix}-#{Time.now.to_i}-#{rand(100_000)}"
  end

  it "catalog and account" do
    expect(@public.catalog.currencies.currencies).not_to be_empty
    expect(@public.catalog.exchange_rates(currency_from: "BTC").first_page.items).to be_an(Array)
    expect(@client.account.balance.merchant).not_to be_empty
    expect(@client.account.referral.code).to be_a(String)
    expect([true, false]).to include(@client.account.vrcs.enabled)
    expect([true, false]).to include(@client.account.vrcs(false).enabled)
  end

  it "payments: lookups, qr, services, public checkout, batch, cancel, history" do
    expect(@client.payments.get(@invoice.uuid).uuid).to eq(@invoice.uuid)
    # Sandbox invoices carry a synthetic `sandbox:` address, which the core deliberately does not
    # render into a QR — the fields come back empty. A real invoice returns a data URI.
    expect(@client.payments.qr(@invoice.uuid).image).to be_a(String)
    expect(@client.payments.services(limit: 5).first_page.items).not_to be_empty
    expect(@public.payments.public_view(@invoice.uuid).status).to eq("created")
    expect(@public.payments.public_qr(@invoice.uuid).image).to be_a(String)

    multi = @client.payments.create(amount: "10", currency: "USDT", order_id: unique("sw-multi"))
    expect(@public.payments.select(multi.uuid, currency: "USDT", network: "tron").network).to eq("tron")

    LiveHelper.accept { @client.payments.resend(@invoice.uuid) }
    LiveHelper.accept { @client.payments.send_email(uuid: @invoice.uuid) }

    batch = @client.payments.batch(on_error: "continue",
                                   payments: [{ amount: "3", currency: "USDT", network: "tron",
                                                order_id: unique("sw-b") }])
    expect(batch.batch_id).not_to be_empty
    expect(@client.batches.info(batch.batch_id).batch_id).to eq(batch.batch_id)

    to_cancel = @client.payments.create(amount: "1", currency: "USDT", network: "tron",
                                        order_id: unique("sw-c"))
    expect(@client.payments.cancel(to_cancel.uuid).status).to eq("cancelled")
    @client.payments.history(limit: 2).first(3).each { |p| expect(p.uuid).not_to be_empty }
  end

  it "deposit → paid → refund, resolve, refund batch" do
    @client.sandbox.deposit(invoice_id: @invoice.uuid, amount: "25", confirmations: 20,
                            txid: unique("sw-tx"))
    expect(%w[paid confirm_check]).to include(@client.payments.get(@invoice.uuid).status)
    LiveHelper.accept do
      @client.refunds.create(uuid: @invoice.uuid, address: LiveHelper::ADDRESS, amount: "5",
                             reference: unique("sw-r"))
    end
    LiveHelper.accept { @client.refunds.resolve(uuid: @invoice.uuid, action: "accept") }
    LiveHelper.accept do
      @client.refunds.batch(refunds: [{ uuid: @invoice.uuid, address: LiveHelper::ADDRESS,
                                        amount: "1", reference: unique("sw-rb") }])
    end
  end

  it "payouts: calculate, validate, create, info, cancel, mass, batch, services, fee configs" do
    expect(@client.payouts.calculate(amount: "10", currency: "USDT", network: "tron").currency)
      .to eq("USDT")
    expect(@client.payouts.validate(amount: "10", currency: "USDT", network: "tron",
                                    address: LiveHelper::ADDRESS).valid).to be(true)

    payout = @client.payouts.create(amount: "10", currency: "USDT", network: "tron",
                                    address: LiveHelper::ADDRESS, order_id: unique("sw-po"))
    expect(@client.payouts.get(order_id: payout.order_id).uuid).to eq(payout.uuid)
    LiveHelper.accept { @client.payouts.cancel(payout.uuid) }
    LiveHelper.accept { @client.payouts.approve(payout.uuid) }

    mass = @client.payouts.mass(payouts: [{ amount: "1", currency: "USDT", network: "tron",
                                            address: LiveHelper::ADDRESS, order_id: unique("sw-m") }])
    expect(mass.first.idx).to eq(0)

    batch = @client.payouts.batch(payouts: [{ amount: "1", currency: "USDT", network: "tron",
                                              address: LiveHelper::ADDRESS, order_id: unique("sw-pb") }])
    expect(batch.batch_id).not_to be_empty
    expect(@client.payouts.services.first_page.items).not_to be_empty

    expect([true, false]).to include(@client.payouts.set_fee_config(fee_on_recipient: true).fee_on_recipient)
    expect([true, false]).to include(@client.payouts.get_fee_config.fee_on_recipient)
    expect([true, false]).to include(@client.payouts.set_refund_fee_config(fee_on_customer: true).fee_on_customer)
    expect([true, false]).to include(@client.payouts.get_refund_fee_config.fee_on_customer)
    expect(@client.payouts.history(kind: "refund", limit: 5).first_page.items).to be_an(Array)
  end

  it "payout links: create, info, list, claim preview/claim, cancel, batch" do
    link = @client.payout_links.create(amount: "5", currency: "USDT", network: "tron",
                                       reference: unique("sw-pl"), title: "Bonus",
                                       expires_in_seconds: 3600)
    @link = link
    expect(link.claim_token).not_to be_nil
    expect(@client.payout_links.get(link.link_id).status).to eq("funded")
    expect(@client.payout_links.list(limit: 5).first_page.items).not_to be_empty
    expect(@public.payout_links.claim_preview(link.claim_token).claimable).to be(true)
    expect(@public.payout_links.claim(link.claim_token, address: LiveHelper::ADDRESS).payout_id)
      .not_to be_empty

    second = @client.payout_links.create(amount: "1", currency: "USDT", network: "tron",
                                         reference: unique("sw-pl2"))
    expect(@client.payout_links.cancel(second.link_id).status).to eq("cancelled")

    batch = @client.payout_links.batch(items: [{ amount: "1", currency: "USDT", network: "tron",
                                                 reference: unique("sw-plb") }])
    expect(batch.first.ok).to be(true)
    expect(batch.first.result).to be_a(Oblodai::Models::PayoutLink)
  end

  it "payment links: create, info, list, toggle, public view, checkout" do
    created = @client.payment_links.create(title: "Tip", amount_mode: "fixed", currency: "USDT",
                                           amount_fixed: "10", pinned_network: "tron")
    expect(created.link_id).not_to be_empty
    expect(@client.payment_links.get(created.link_id).active).to be(true)
    expect(@client.payment_links.list.first_page.items).not_to be_empty
    expect(@public.payment_links.public_view(created.link_id).amount_mode).to eq("fixed")
    expect(@public.payment_links.checkout(created.link_id, currency: "USDT", network: "tron").uuid)
      .not_to be_empty
    expect(@client.payment_links.toggle(created.link_id, false).active).to be(false)
  end

  it "splits and settings" do
    rule = @client.splits.create_rule(percent: "10", address: LiveHelper::ADDRESS, network: "tron",
                                      note: "partner")
    expect(@client.splits.list_rules.map(&:rule_id)).to include(rule.rule_id)
    expect(@client.splits.set_config(refund_hold_seconds: 3600).refund_hold_seconds).to eq(3600)
    expect(@client.splits.get_config.refund_hold_seconds).to eq(3600)
    expect(@client.splits.set_opt_in(true).enabled).to be(true)
    expect(@client.splits.get_opt_in.enabled).to be(true)
    expect(@client.splits.delete_rule(rule.rule_id).ok).to be(true)

    settings = @client.settings
    expect(settings.set_discount(currency: "USDT", network: "tron", discount_percent: 2).discount_percent)
      .to eq(2)
    expect(settings.list_discounts.first_page.items).not_to be_empty
    expect(settings.set_accuracy(enabled: true, accuracy_percent: 2).enabled).to be(true)
    expect(settings.get_accuracy.enabled).to be(true)
    expect(settings.set_auto_refund(overpay: true, underpay: false).overpay).to be(true)
    expect([true, false]).to include(settings.get_auto_refund.configured)
    expect(settings.set_accepted(accepted: [{ currency: "USDT", network: "tron" }]).ok).to be(true)
    expect(settings.list_accepted.first_page.items).to be_an(Array)
    expect(settings.set_payment_fee_config(payer_pays_percent: 50).payer_pays_percent).to eq(50)
    expect(settings.get_payment_fee_config.payer_pays_percent).to eq(50)

    expect(settings.set_auto_withdraw(currency: "USDT", network: "tron",
                                      address: LiveHelper::ADDRESS, min_amount: "100")).not_to be_empty
    expect(settings.list_auto_withdraw).to be_an(Array)
    expect(settings.delete_auto_withdraw("USDT")).to be_an(Array)

    expect(settings.add_api_allowlist("203.0.113.0/24").items).to include("203.0.113.0/24")
    expect(settings.list_api_allowlist.items).to include("203.0.113.0/24")
    expect(settings.enable_api_allowlist(false).enabled).to be(false)
    expect(settings.remove_api_allowlist("203.0.113.0/24").items).not_to include("203.0.113.0/24")
  end

  it "webhooks and the sandbox inspector" do
    endpoint = @client.webhooks.register(LiveHelper::HOOK)
    expect(endpoint.endpoint_id).not_to be_empty
    expect(@client.webhooks.rotate_secret.secret).not_to be_empty
    expect(@client.webhooks.deliveries(limit: 5).first_page.items).to be_an(Array)
    LiveHelper.accept do
      @client.webhooks.test("payment", url_callback: LiveHelper::HOOK, currency: "USDT",
                                       network: "tron", status: "paid")
    end
    LiveHelper.accept { @client.webhooks.test_legacy(url: LiveHelper::HOOK, status: "paid") }

    inspector = @client.sandbox.webhooks(limit: 5).first_page
    expect(inspector.items).to be_an(Array)
    terminal = inspector.items.find { |d| %w[delivered dead].include?(d.status) }
    LiveHelper.accept { @client.sandbox.replay(terminal.id) } if terminal
  end

  it "wallets and transfers (refused for a dev store, as documented)" do
    LiveHelper.accept { @client.wallets.create(currency: "USDT", network: "tron", order_id: unique("sw-w")) }
    LiveHelper.accept { @client.wallets.qr(LiveHelper::ADDRESS) }
    LiveHelper.accept { @client.wallets.block(address: LiveHelper::ADDRESS) }
    # A well-formed uuid that does not exist: the refusal must be a business one (404), not a
    # complaint about the shape of what the SDK sent.
    LiveHelper.accept do
      @client.wallets.refund_blocked_deposit(uuid: SecureRandom.uuid, address: LiveHelper::ADDRESS)
    end
    LiveHelper.accept { @client.transfers.to_personal(amount: "1", currency: "USDT") }
    recipient = SecureRandom.uuid # a platform user id that does not exist: a 404, not a shape error
    LiveHelper.accept { @client.transfers.to_user(to_user_id: recipient, amount: "1", currency: "USDT") }
    LiveHelper.accept do
      @client.transfers.batch(transfers: [{ to_user_id: recipient, amount: "1", currency: "USDT",
                                            order_id: unique("sw-tb") }])
    end
  end

  it "documents (when the stand has a renderer)" do
    skip "the stand reports documents disabled" unless @docs_enabled

    statement = @client.documents.statement(from: "2026-01-01", to: "2026-12-31", lang: "en")
    expect(statement.content_type).to match(/pdf/)
    expect(statement.size).to be > 0
    expect(@client.documents.fee_schedule.size).to be > 0
    expect(@client.documents.ledger(format: "csv").content_type).to match(/csv|pdf/)
    LiveHelper.accept { @client.documents.referrals_report(lang: "en") }

    job = @client.documents.create_job(kind: "statement", format: "csv", lang: "en",
                                       from: "2026-01-01", to: "2026-12-31")
    expect(@client.documents.job_info(job.job_id).job_id).to eq(job.job_id)
    LiveHelper.accept { @client.documents.job_file(job.job_id) }

    info = @client.payments.get(@invoice.uuid)
    uri = URI.parse(info.document_url)
    kind, id = uri.path.split("/")[3, 2]
    query = URI.decode_www_form(uri.query.to_s).to_h
    document = @public.documents.download(kind, id, exp: query["exp"].to_i, sig: query["sig"])
    expect(document.content_type).to match(/pdf/)
  end

  it "sandbox reset last" do
    expect(@client.sandbox.reset.invoices_cancelled).to be_a(Integer)
  end
end
