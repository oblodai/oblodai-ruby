# frozen_string_literal: true

require_relative "common"

module Oblodai
  module Models
    # The merchant's API key as minted by onboarding: one pair, and it signs every signed route.
    # The secret is shown once — here — and never again.
    class ApiKeyPair < Model
      # @return [String] goes into `X-Public-Id` (`oblodai_…`; `test_oblodai_…` in the sandbox)
      field :public_id
      # @return [String] signs the request; store it in a secret manager. Kept out of `to_h`,
      #   `to_json` and `inspect`.
      field :secret, secret: true
    end

    # `POST /v1/merchants` — a freshly provisioned merchant and its keys.
    class MerchantOnboarded < Model
      # @return [String]
      field :merchant_id
      # @return [String] the merchant's default project (store)
      field :project_id
      # @return [Oblodai::Models::ApiKeyPair] the merchant's one API key; it signs every signed
      #   route, and its secret is shown here and never again
      field :api_key, model: ApiKeyPair
    end

    # `POST /v1/merchants/{id}/sandbox` — the merchant's dev store and its own `test_` API key.
    class SandboxStore < MerchantOnboarded
      # @return [Boolean] false when the dev store already existed (the call is idempotent)
      field :created
    end
  end
end
