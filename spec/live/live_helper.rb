# frozen_string_literal: true

require "net/http"

# Shared setup for the live suites: they run against a REAL core at OBLODAI_LIVE_URL
# (`rake spec:live`, or `OBLODAI_LIVE_URL=http://127.0.0.1:8095 rspec spec/live`). Onboarding is
# open on a dev stand: `POST /v1/merchants` (outside the merchant API, so called directly) then
# `sandbox.onboard_store` mints a sandbox key pair, and the money path runs with it — signature,
# envelope, idempotency and webhooks all exercised for real.
module LiveHelper
  BASE = ENV.fetch("OBLODAI_LIVE_URL", "http://127.0.0.1:8095")
  ADDRESS = "TQrY8bkbpXKPt2LZbU8jqfnpFbUSF15sbx"
  HOOK = ENV.fetch("OBLODAI_LIVE_HOOK_URL", "http://127.0.0.1:8096/hook")

  module_function

  # @return [Oblodai::Client] a client with no credentials — public routes only
  def public_client
    Oblodai::Client.new(base_url: BASE, allow_insecure_base_url: true, env: {})
  end

  # Provision a merchant and its dev store, and return a client holding the sandbox key.
  # @return [Array(Oblodai::Client, String)] the client and the merchant id
  def sandbox_client(label)
    uri = URI.join(BASE, "/v1/merchants")
    email = "#{label}-#{Time.now.to_i}-#{rand(10_000)}@example.com"
    answer = Net::HTTP.post(uri, JSON.generate(email: email, name: "SDK #{label}"),
                            "Content-Type" => "application/json")
    merchant_id = JSON.parse(answer.body).dig("result", "merchant_id")
    onboarding = Oblodai::Client.new(base_url: BASE, allow_insecure_base_url: true, env: {},
                                     admin_token: ENV.fetch("OBLODAI_ADMIN_TOKEN", nil))
    store = onboarding.sandbox.onboard_store(merchant_id)
    client = Oblodai::Client.new(public_id: store.api_key.public_id, secret: store.api_key.secret,
                                 base_url: BASE, allow_insecure_base_url: true, env: {})
    [client, store.merchant_id]
  end

  # @return [String] a value no earlier run used
  def unique(prefix)
    "#{prefix}-#{Time.now.to_i}-#{rand(100_000)}"
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
