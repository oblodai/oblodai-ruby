# frozen_string_literal: true

require_relative "common"

module Oblodai
  module Models
    # An API key pair as minted by onboarding. The secret is shown once.
    class ApiKeyPair < Model
      # @return [String] goes into `X-Public-Id`
      field :public_id
      # @return [String] signs the request; store it in a secret manager
      field :secret
      # @return [String] "api" — the unified key kind current merchants receive
      field :kind
    end

    # `POST /v1/merchants` — a freshly provisioned merchant and its keys.
    class MerchantOnboarded < Model
      # @return [String]
      field :merchant_id
      # @return [String] the merchant's default project (store)
      field :project_id
      # @return [Oblodai::Models::ApiKeyPair] the unified key
      field :api_key, model: ApiKeyPair
      # @return [Oblodai::Models::ApiKeyPair]
      field :payment_key, model: ApiKeyPair
      # @return [Oblodai::Models::ApiKeyPair]
      field :payout_key, model: ApiKeyPair
    end

    # `POST /v1/merchants/{id}/sandbox` — the merchant's dev store and its `test_` key.
    class SandboxStore < MerchantOnboarded
      # @return [Boolean] false when the dev store already existed (the call is idempotent)
      field :created
    end
  end
end
