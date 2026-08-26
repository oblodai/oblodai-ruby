# frozen_string_literal: true

require_relative "base"
require_relative "../models/account"
require_relative "../models/catalog"
require_relative "../models/sandbox"
require_relative "../models/merchants"
require_relative "../models/webhooks"

module Oblodai
  module Resources
    # Balances and account-level facts.
    class Account < Base
      # `POST /v1/balance` — available balance per currency.
      # @return [Oblodai::Models::Balance]
      def balance(**options)
        call("POST /v1/balance", nil, model: Models::Balance, **options)
      end

      # `POST /v1/referral/info` — referral code, link and earnings.
      # @return [Oblodai::Models::ReferralInfo]
      def referral(**options)
        call("POST /v1/referral/info", nil, model: Models::ReferralInfo, **options)
      end

      # `POST /v1/vrcs` — read (no argument) or set volatility-risk conversion (auto-convert
      # volatile deposits to USDT).
      # @param enabled [Boolean, nil]
      # @return [Oblodai::Models::VrcsStatus]
      def vrcs(enabled = nil, **options)
        body = enabled.nil? ? nil : { enabled: enabled }
        call("POST /v1/vrcs", body, model: Models::VrcsStatus, **options)
      end
    end

    # Public reference data — no credentials needed.
    class Catalog < Base
      # `GET /v1/currencies` — every asset, its networks and live availability.
      # @return [Oblodai::Models::Currencies]
      def currencies(**options)
        call("GET /v1/currencies", nil, model: Models::Currencies, **options)
      end

      # `POST /v1/exchange-rate/list` — current rates, optionally filtered by `currency_from` /
      # `currency_to`.
      # @return [Oblodai::Page<Oblodai::Models::ExchangeRate>]
      def exchange_rates(**params)
        options = Base.take_options!(params)
        page("POST /v1/exchange-rate/list", model: Models::ExchangeRate, params: params, **options)
      end
    end

    # Developer sandbox (`test_` keys only): fake money, simulated deposits, webhook inspector.
    class Sandbox < Base
      # `POST /v1/sandbox/faucet` — credit test funds.
      # @return [Oblodai::Models::FaucetResult]
      def faucet(**params)
        options = Base.take_options!(params)
        call("POST /v1/sandbox/faucet", params, model: Models::FaucetResult, **options)
      end

      # `POST /v1/sandbox/deposit` — simulate an on-chain deposit to an invoice (repeat the txid to
      # add confirmations).
      # @return [Oblodai::Models::SandboxDeposit]
      def deposit(**params)
        options = Base.take_options!(params)
        call("POST /v1/sandbox/deposit", params, model: Models::SandboxDeposit, **options)
      end

      # `GET /v1/sandbox/webhooks` — deliveries with their payloads.
      # @return [Oblodai::Page<Oblodai::Models::WebhookDelivery>]
      def webhooks(**params)
        options = Base.take_options!(params)
        page("GET /v1/sandbox/webhooks", model: Models::WebhookDelivery, params: params, **options)
      end

      # `POST /v1/sandbox/webhooks/replay` — re-send a terminal (delivered/dead) delivery.
      # @param delivery_id [String, Oblodai::Models::WebhookDelivery] the delivery, or its id
      # @return [Oblodai::Models::SandboxReplay]
      def replay(delivery_id, **options)
        call("POST /v1/sandbox/webhooks/replay", { delivery_id: id_of(delivery_id, :id) },
             model: Models::SandboxReplay, **options)
      end

      # `POST /v1/sandbox/reset` — cancel open invoices and zero balances.
      # @return [Oblodai::Models::SandboxReset]
      def reset(**options)
        call("POST /v1/sandbox/reset", nil, model: Models::SandboxReset, **options)
      end
    end

    # Merchant provisioning — for platforms that onboard merchants themselves. These routes are not
    # HMAC-signed; a self-hosted gateway gates them with its admin token (`admin_token:` option).
    class Merchants < Base
      # `POST /v1/merchants` — create a merchant and mint its API key (the secret is shown once).
      # @return [Oblodai::Models::MerchantOnboarded]
      def create(**params)
        options = Base.take_options!(params)
        call("POST /v1/merchants", params, model: Models::MerchantOnboarded, **options)
      end

      # `POST /v1/merchants/{id}/sandbox` — the merchant's dev store and its `test_` key (idempotent).
      # @param merchant_id [String, Oblodai::Models::MerchantOnboarded] the merchant, or its id
      # @return [Oblodai::Models::SandboxStore]
      def create_sandbox(merchant_id, **options)
        call("POST /v1/merchants/{id}/sandbox", nil, model: Models::SandboxStore,
                                                     path_params: { id: id_of(merchant_id, :merchant_id) },
                                                     **options)
      end
    end
  end
end
