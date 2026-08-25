# frozen_string_literal: true

# Shared setup for the live suites: they run against a REAL core at OBLODAI_LIVE_URL
# (`rake spec:live`, or `OBLODAI_LIVE_URL=http://127.0.0.1:8095 rspec spec/live`). Onboarding is
# open on a self-hosted core, so each run provisions its own merchant and dev store and drives the
# money path with a sandbox key — signature, envelope, idempotency and webhooks all exercised for real.
module LiveHelper
  BASE = ENV.fetch("OBLODAI_LIVE_URL", "http://127.0.0.1:8095")
  ADDRESS = "TQrY8bkbpXKPt2LZbU8jqfnpFbUSF15sbx"
  HOOK = ENV.fetch("OBLODAI_LIVE_HOOK_URL", "http://127.0.0.1:8096/hook")

  module_function

  # @return [Oblodai::Client] a client with no credentials — public routes only
  def public_client
    Oblodai::Client.new(base_url: BASE, allow_insecure_base_url: true)
  end

  # Provision a merchant and its dev store, and return a client holding the sandbox key.
  # @return [Array(Oblodai::Client, String)] the client and the merchant id
  def sandbox_client(label)
    onboarding = Oblodai::Client.new(base_url: BASE, allow_insecure_base_url: true,
                                     admin_token: ENV.fetch("OBLODAI_ADMIN_TOKEN", nil))
    merchant = onboarding.merchants.create(email: "#{label}-#{Time.now.to_i}-#{rand(10_000)}@example.com",
                                           name: "SDK #{label}")
    store = onboarding.merchants.create_sandbox(merchant.merchant_id)
    client = Oblodai::Client.new(public_id: store.api_key.public_id, secret: store.api_key.secret,
                                 base_url: BASE, allow_insecure_base_url: true)
    [client, store.merchant_id]
  end

  # Fails the spec on SDK-side contract/shape problems; tolerates business refusals (409/403/404).
  def accept
    yield
  rescue Oblodai::ContractError, Oblodai::ValidationError
    raise
  rescue Oblodai::Error
    nil
  end
end
