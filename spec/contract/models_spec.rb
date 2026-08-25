# frozen_string_literal: true

# Wire models versus the golden bodies the core recorded. Each row names a route, how to reach the
# object inside its result, and the model's key set. Keys must match EXACTLY: a field the core
# stopped sending fails here, and so does a field it started sending that the model lacks.
MODELS = Oblodai::Models

MODEL_ROWS = [
  ["POST /v1/payment", ->(r) { r }, MODELS::Payment],
  ["POST /v1/payment/info", ->(r) { r }, MODELS::Payment, %i[refunds refund_status]],
  ["POST /v1/payment/cancel", ->(r) { r }, MODELS::Payment],
  ["POST /v1/payment/history", ->(r) { r["items"][0] }, MODELS::Payment],
  ["GET /v1/pay/{id}", ->(r) { r }, MODELS::PublicPayment],
  ["POST /v1/pay/{id}/select", ->(r) { r }, MODELS::PublicPayment],
  ["POST /v1/link/{id}/checkout", ->(r) { r }, MODELS::PublicPayment],
  ["POST /v1/payment/qr", ->(r) { r }, MODELS::QrCode],
  ["GET /v1/pay/{id}/qr", ->(r) { r }, MODELS::QrCode],
  ["POST /v1/payment/services", ->(r) { r["items"][0] }, MODELS::ServiceMethod],
  ["POST /v1/payout/services", ->(r) { r["items"][0] }, MODELS::ServiceMethod],
  ["POST /v1/payment/batch", ->(r) { r }, MODELS::BatchSubmitted],
  ["POST /v1/payout/batch", ->(r) { r }, MODELS::BatchSubmitted],
  ["POST /v1/refund/batch", ->(r) { r }, MODELS::BatchSubmitted],
  ["POST /v1/transfer/batch", ->(r) { r }, MODELS::BatchSubmitted],
  ["POST /v1/batch/info", ->(r) { r }, MODELS::BatchInfo],
  ["POST /v1/payout", ->(r) { r }, MODELS::Payout],
  ["POST /v1/payout/info", ->(r) { r }, MODELS::Payout, %i[error error_code]],
  ["POST /v1/payout/cancel", ->(r) { r }, MODELS::Payout],
  ["POST /v1/payout/history", ->(r) { r["items"][0] }, MODELS::Payout],
  ["POST /v1/payout/mass", ->(r) { r["items"][0]["result"] }, MODELS::Payout],
  ["POST /v1/payment/refund", ->(r) { r }, MODELS::Payout],
  ["POST /v1/payment/resolve", ->(r) { r }, MODELS::Payout, [], %i[resolution]],
  ["POST /v1/wallet/blocked-address-refund", ->(r) { r }, MODELS::Payout, [], %i[wallet_uuid]],
  ["POST /v1/payout/calculate", ->(r) { r }, MODELS::PayoutCalculation],
  ["POST /v1/payout/validate", ->(r) { r }, MODELS::PayoutValidation],
  ["POST /v1/payout/link", ->(r) { r }, MODELS::PayoutLink, %i[claim_token claim_url]],
  ["POST /v1/payout/link/info", ->(r) { r }, MODELS::PayoutLink],
  ["POST /v1/payout/link/list", ->(r) { r["items"][0] }, MODELS::PayoutLink],
  ["POST /v1/payout/link/cancel", ->(r) { r }, MODELS::PayoutLink],
  ["POST /v1/payout/link/batch", ->(r) { r["items"][0]["result"] }, MODELS::PayoutLink,
   %i[claim_token claim_url batch_id]],
  ["GET /v1/claim/{token}", ->(r) { r }, MODELS::ClaimPreview],
  ["POST /v1/claim/{token}", ->(r) { r }, MODELS::ClaimResult],
  ["POST /v1/payment/link", ->(r) { r }, MODELS::PaymentLinkCreated],
  ["POST /v1/payment/link/info", ->(r) { r }, MODELS::PaymentLink, %i[payments]],
  ["POST /v1/payment/link/list", ->(r) { r["items"][0] }, MODELS::PaymentLink],
  ["GET /v1/link/{id}", ->(r) { r }, MODELS::PublicPaymentLink],
  ["POST /v1/payment/link/toggle", ->(r) { r }, MODELS::PaymentLinkToggled],
  ["POST /v1/balance", ->(r) { r }, MODELS::Balance],
  ["POST /v1/referral/info", ->(r) { r }, MODELS::ReferralInfo],
  ["POST /v1/vrcs", ->(r) { r }, MODELS::VrcsStatus],
  ["POST /v1/auto-withdraw/list", ->(r) { r["items"][0] }, MODELS::AutoWithdrawRule],
  ["POST /v1/auto-withdraw/set", ->(r) { r["items"][0] }, MODELS::AutoWithdrawRule],
  ["POST /v1/auto-withdraw/delete", ->(r) { r }, nil, [], %i[items]],
  ["POST /v1/api-allowlist/list", ->(r) { r }, MODELS::ApiAllowlist],
  ["POST /v1/api-allowlist/add", ->(r) { r }, MODELS::ApiAllowlist],
  ["POST /v1/api-allowlist/remove", ->(r) { r }, MODELS::ApiAllowlist],
  ["POST /v1/api-allowlist/enable", ->(r) { r }, MODELS::ApiAllowlist],
  ["POST /v1/payment/discount/list", ->(r) { r["items"][0] }, MODELS::DiscountRule],
  ["POST /v1/payment/discount/set", ->(r) { r }, MODELS::DiscountRule],
  ["POST /v1/payment/accuracy/get", ->(r) { r }, MODELS::AccuracyConfig],
  ["POST /v1/payment/accuracy/set", ->(r) { r }, MODELS::AccuracyConfig],
  ["POST /v1/payment/autorefund/get", ->(r) { r }, MODELS::AutoRefundConfig, %i[configured]],
  ["POST /v1/payment/autorefund/set", ->(r) { r }, MODELS::AutoRefundConfig, %i[configured]],
  ["POST /v1/payment/accepted/list", ->(r) { r["items"][0] }, MODELS::AcceptedMethod, %i[reason]],
  ["POST /v1/payment/accepted/set", ->(r) { r }, MODELS::OkResult],
  ["POST /v1/payment/fee-config/get", ->(r) { r }, MODELS::PaymentFeeConfig, %i[enabled]],
  ["POST /v1/payment/fee-config/set", ->(r) { r }, MODELS::PaymentFeeConfig, %i[enabled]],
  ["POST /v1/payout/fee-config/get", ->(r) { r }, MODELS::PayoutFeeConfig, %i[configured]],
  ["POST /v1/payout/fee-config/set", ->(r) { r }, MODELS::PayoutFeeConfig, %i[configured]],
  ["POST /v1/payout/refund-fee-config/get", ->(r) { r }, MODELS::RefundFeeConfig, %i[configured]],
  ["POST /v1/payout/refund-fee-config/set", ->(r) { r }, MODELS::RefundFeeConfig, %i[configured]],
  ["POST /v1/split/rule", ->(r) { r }, nil, [], %i[rule_id percent]],
  ["POST /v1/split/rule/list", ->(r) { r["items"][0] }, MODELS::SplitRule],
  ["POST /v1/split/rule/delete", ->(r) { r }, MODELS::OkResult],
  ["POST /v1/split/config/get", ->(r) { r }, MODELS::SplitConfig],
  ["POST /v1/split/config/set", ->(r) { r }, MODELS::SplitConfig],
  ["POST /v1/split/recipient/optin", ->(r) { r }, MODELS::SplitOptIn],
  ["POST /v1/split/recipient/optin/get", ->(r) { r }, MODELS::SplitOptIn],
  ["GET /v1/currencies", ->(r) { r }, MODELS::Currencies],
  ["GET /v1/currencies", ->(r) { r["currencies"][0]["networks"][0] }, MODELS::CurrencyNetwork, %i[contract]],
  ["POST /v1/exchange-rate/list", ->(r) { r["items"][0] }, MODELS::ExchangeRate],
  ["POST /v1/webhooks", ->(r) { r }, MODELS::WebhookEndpoint, %i[secret]],
  ["POST /v1/webhooks/rotate-secret", ->(r) { r }, MODELS::WebhookSecretRotated],
  ["POST /v1/webhooks/deliveries", ->(r) { r["items"][0] }, MODELS::WebhookDelivery],
  ["GET /v1/sandbox/webhooks", ->(r) { r["items"][0] }, MODELS::WebhookDelivery, %i[payload sequence]],
  ["POST /v1/test-webhook/payment", ->(r) { r }, MODELS::WebhookTestResult],
  ["POST /v1/test-webhook/payout", ->(r) { r }, MODELS::WebhookTestResult],
  ["POST /v1/test-webhook/wallet", ->(r) { r }, MODELS::WebhookTestResult],
  ["POST /v1/payment/testing-webhook", ->(r) { r }, MODELS::WebhookTestResult, [], %i[url duration_ms]],
  ["POST /v1/payment/send-email", ->(r) { r }, MODELS::EmailSent],
  ["POST /v1/payment/resend", ->(r) { r }, MODELS::OkResult],
  ["POST /v1/wallet", ->(r) { r }, MODELS::Wallet, %i[destination_tag memo address_xaddress address_muxed]],
  ["POST /v1/wallet/block", ->(r) { r }, MODELS::WalletBlocked],
  ["POST /v1/wallet/qr", ->(r) { r }, MODELS::WalletQr],
  ["POST /v1/transfer/to-personal", ->(r) { r }, MODELS::TransferToPersonal],
  ["POST /v1/transfer/to-user", ->(r) { r }, MODELS::TransferToUser],
  ["POST /v1/documents/jobs", ->(r) { r }, MODELS::DocumentJob, %i[ready_within file error]],
  ["POST /v1/documents/jobs/info", ->(r) { r }, MODELS::DocumentJob, %i[ready_within file error]],
  ["POST /v1/documents/jobs/info", ->(r) { r["file"] }, MODELS::DocumentJobFile],
  ["POST /v1/sandbox/faucet", ->(r) { r }, MODELS::FaucetResult],
  ["POST /v1/sandbox/deposit", ->(r) { r }, MODELS::SandboxDeposit],
  ["POST /v1/sandbox/reset", ->(r) { r }, MODELS::SandboxReset],
  ["POST /v1/sandbox/webhooks/replay", ->(r) { r }, MODELS::SandboxReplay],
  ["POST /v1/merchants", ->(r) { r }, MODELS::MerchantOnboarded],
  ["POST /v1/merchants", ->(r) { r["api_key"] }, MODELS::ApiKeyPair],
  ["POST /v1/merchants/{id}/sandbox", ->(r) { r }, MODELS::SandboxStore]
].freeze

# Routes the API guarantees to refuse for API keys (no success body exists to model).
NOT_MODELLED = ["POST /v1/payout/approve"].freeze

RSpec.describe "wire models match the golden bodies" do
  def key_diff(actual, expected, optional)
    actual = actual.map(&:to_s)
    expected = expected.map(&:to_s)
    optional = optional.map(&:to_s)
    { missing_on_wire: expected - actual - optional, unknown_on_wire: actual - expected - optional }
  end

  MODEL_ROWS.each do |route, picker, model, optional, extra|
    keys = (model ? model.keys : []) + (extra || [])
    it "#{route} → #{model || "raw"} (#{keys.size} keys)" do
      fx = Fixtures.fixtures[route]
      skip "recorded as a refusal in this environment" if fx.nil? || fx["status"] >= 300

      object = picker.call(fx.dig("response", "result"))
      expect(object).to be_truthy, "#{route}: picker found nothing"
      expect(key_diff(object.keys, keys, optional || []))
        .to eq(missing_on_wire: [], unknown_on_wire: []), "#{route}: model keys drifted from the wire"

      next if model.nil?

      decoded = model.from(object)
      expect(decoded).to be_a(model)
      # Decoding is lossless: everything the core sent comes back out.
      expect(decoded.to_h.keys.map(&:to_s)).to match_array(object.keys)
    end
  end

  it "covers every recorded success body with a model row" do
    covered = MODEL_ROWS.map(&:first).uniq
    Fixtures.fixtures.each do |route, fx|
      next unless (200..299).cover?(fx["status"])
      next if NOT_MODELLED.include?(route)
      next unless fx.dig("headers", "Content-Type").to_s.include?("json")

      expect(covered).to include(route), "#{route}: recorded success body has no model row"
    end
  end
end

RSpec.describe "vocabularies cover what the wire carries" do
  it "statuses in the golden bodies are in the enums" do
    Fixtures.result_of("POST /v1/payment/history")["items"].each do |payment|
      expect(Oblodai::Enums::PAYMENT_STATUSES).to include(payment["status"])
    end
    Fixtures.result_of("POST /v1/payout/history")["items"].each do |payout|
      expect(Oblodai::Enums::PAYOUT_STATUSES).to include(payout["status"])
    end
    Fixtures.result_of("POST /v1/payout/link/list")["items"].each do |link|
      expect(Oblodai::Enums::PAYOUT_LINK_STATUSES).to include(link["status"])
    end
    Fixtures.result_of("POST /v1/webhooks/deliveries")["items"].each do |delivery|
      expect(Oblodai::Enums::DELIVERY_STATUSES).to include(delivery["status"])
    end
    Fixtures.result_of("GET /v1/currencies")["currencies"].each do |currency|
      currency["networks"].each { |n| expect(Oblodai::Enums::NETWORKS).to include(n["network"]) }
    end
  end

  it "webhook samples carry known event types and bodies matching the event models" do
    Fixtures.webhook_samples.each do |sample|
      expect(Oblodai::Enums::EVENT_TYPES).to include(sample["headers"]["X-Webhook-Event"])
      model = Oblodai::Webhooks::EVENT_MODELS.fetch(sample["body"]["type"])
      expect(model.keys.map(&:to_s)).to match_array(sample["body"].keys)
    end
  end

  it "every recorded error code is a known code with the documented envelope" do
    Fixtures.error_samples.each do |code, fx|
      expect(Oblodai::Enums::ERROR_CODES).to include(code)
      error = fx.dig("response", "error")
      expect(error["code"]).to eq(code)
      expect([true, false]).to include(error["retryable"])
      expect(error["request_id"]).to be_a(String)
      expect(error["retry_after"]).to be > 0 if fx["status"] == 429
    end
  end

  it "turns every recorded error envelope into the right error class" do
    Fixtures.error_samples.each do |code, fx|
      error = Oblodai.api_error_from(fx["status"], fx.dig("response", "error"))
      expect(error.code).to eq(code)
      expect(error.http_status).to eq(fx["status"])
      expect(error.retryable?).to eq(fx.dig("response", "error", "retryable"))
      expect(error).to be_a(Oblodai::ApiError)
      expect(error).not_to be_synthetic
    end
  end

  it "documents every field the recorded journeys sent" do
    Fixtures.fixtures.each do |route, fx|
      documented = Oblodai::Contract::REQUESTS[route]
      next if documented.nil? || !fx["request"].is_a?(Hash)

      fx["request"].each_key do |field|
        expect(documented).to have_key(field.to_sym),
                              "#{route}: journey sent undocumented field \"#{field}\""
      end
    end
  end
end
