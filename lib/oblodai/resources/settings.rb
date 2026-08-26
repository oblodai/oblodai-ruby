# frozen_string_literal: true

require_relative "base"
require_relative "../models/account"
require_relative "../models/payouts"
require_relative "../models/common"

module Oblodai
  module Resources
    # Merchant-level configuration exposed over the API.
    class Settings < Base
      # `POST /v1/payment/discount/set` — payer-facing discount/markup per currency+network.
      # @return [Oblodai::Models::DiscountRule]
      def set_discount(**params)
        options = Base.take_options!(params)
        call("POST /v1/payment/discount/set", params, model: Models::DiscountRule, **options)
      end

      # `POST /v1/payment/discount/list`.
      # @return [Oblodai::Page<Oblodai::Models::DiscountRule>]
      def list_discounts(**params)
        options = Base.take_options!(params)
        page("POST /v1/payment/discount/list", model: Models::DiscountRule, params: params, **options)
      end

      # `POST /v1/payment/accuracy/get` — under/overpayment tolerance.
      # @return [Oblodai::Models::AccuracyConfig]
      def get_accuracy(**options)
        call("POST /v1/payment/accuracy/get", nil, model: Models::AccuracyConfig, **options)
      end

      # `POST /v1/payment/accuracy/set`.
      # @return [Oblodai::Models::AccuracyConfig]
      def set_accuracy(**params)
        options = Base.take_options!(params)
        call("POST /v1/payment/accuracy/set", params, model: Models::AccuracyConfig, **options)
      end

      # `POST /v1/payment/autorefund/get`.
      # @return [Oblodai::Models::AutoRefundConfig]
      def get_auto_refund(**options)
        call("POST /v1/payment/autorefund/get", nil, model: Models::AutoRefundConfig, **options)
      end

      # `POST /v1/payment/autorefund/set` — refund over/underpayments automatically.
      # @return [Oblodai::Models::AutoRefundConfig]
      def set_auto_refund(**params)
        options = Base.take_options!(params)
        call("POST /v1/payment/autorefund/set", params, model: Models::AutoRefundConfig, **options)
      end

      # `POST /v1/payment/accepted/list` — which currency/network pairs invoices may be paid in.
      # @return [Oblodai::Page<Oblodai::Models::AcceptedMethod>]
      def list_accepted(**params)
        options = Base.take_options!(params)
        page("POST /v1/payment/accepted/list", model: Models::AcceptedMethod, params: params, **options)
      end

      # `POST /v1/payment/accepted/set`.
      # @return [Oblodai::Models::OkResult]
      def set_accepted(**params)
        options = Base.take_options!(params)
        call("POST /v1/payment/accepted/set", params, model: Models::OkResult, **options)
      end

      # `POST /v1/payment/fee-config/get` — share of the network fee charged to the payer.
      # @return [Oblodai::Models::PaymentFeeConfig]
      def get_payment_fee_config(**options)
        call("POST /v1/payment/fee-config/get", nil, model: Models::PaymentFeeConfig, **options)
      end

      # `POST /v1/payment/fee-config/set`.
      # @return [Oblodai::Models::PaymentFeeConfig]
      def set_payment_fee_config(**params)
        options = Base.take_options!(params)
        call("POST /v1/payment/fee-config/set", params, model: Models::PaymentFeeConfig, **options)
      end

      # `POST /v1/auto-withdraw/list`. Payout key.
      # @return [Array<Oblodai::Models::AutoWithdrawRule>]
      def list_auto_withdraw(**options)
        plain_list("POST /v1/auto-withdraw/list", nil, model: Models::AutoWithdrawRule, **options)
      end

      # `POST /v1/auto-withdraw/set` — sweep a currency to an address once the balance passes
      # `min_amount`.
      # @return [Array<Oblodai::Models::AutoWithdrawRule>]
      def set_auto_withdraw(**params)
        options = Base.take_options!(params)
        plain_list("POST /v1/auto-withdraw/set", params, model: Models::AutoWithdrawRule, **options)
      end

      # `POST /v1/auto-withdraw/delete`.
      # @param currency [String]
      # @return [Array<Oblodai::Models::AutoWithdrawRule>]
      def delete_auto_withdraw(currency, **options)
        plain_list("POST /v1/auto-withdraw/delete", { currency: currency },
                   model: Models::AutoWithdrawRule, **options)
      end

      # `POST /v1/api-allowlist/list` — source IPs allowed to use the API keys. Payout key.
      # @return [Oblodai::Models::ApiAllowlist]
      def list_api_allowlist(**options)
        call("POST /v1/api-allowlist/list", nil, model: Models::ApiAllowlist, **options)
      end

      # `POST /v1/api-allowlist/add`.
      # @param cidr [String]
      # @return [Oblodai::Models::ApiAllowlist]
      def add_api_allowlist(cidr, **options)
        call("POST /v1/api-allowlist/add", { cidr: cidr }, model: Models::ApiAllowlist, **options)
      end

      # `POST /v1/api-allowlist/remove`.
      # @param cidr [String]
      # @return [Oblodai::Models::ApiAllowlist]
      def remove_api_allowlist(cidr, **options)
        call("POST /v1/api-allowlist/remove", { cidr: cidr }, model: Models::ApiAllowlist, **options)
      end

      # `POST /v1/api-allowlist/enable` — switch enforcement on or off (the list is kept).
      # @param enabled [Boolean]
      # @return [Oblodai::Models::ApiAllowlist]
      def enable_api_allowlist(enabled, **options)
        call("POST /v1/api-allowlist/enable", { enabled: enabled }, model: Models::ApiAllowlist, **options)
      end
    end

    # Revenue splits: a percentage of every payment forwarded to a partner. Payout key.
    class Splits < Base
      # `POST /v1/split/rule` — to an external address (`address`+`network`) or a platform merchant
      # (`merchant_id`).
      # @return [Oblodai::Models::SplitRule]
      def create_rule(**params)
        options = Base.take_options!(params)
        call("POST /v1/split/rule", params, model: Models::SplitRule, **options)
      end

      # `POST /v1/split/rule/list`.
      # @return [Oblodai::Page<Oblodai::Models::SplitRule>]
      def list_rules(**params)
        options = Base.take_options!(params)
        page("POST /v1/split/rule/list", model: Models::SplitRule, params: params, **options)
      end

      # `POST /v1/split/rule/delete`.
      # @param rule_id [String, Oblodai::Models::SplitRule] the rule, or its `rule_id`
      # @return [Oblodai::Models::OkResult]
      def delete_rule(rule_id, **options)
        call("POST /v1/split/rule/delete", { rule_id: id_of(rule_id, :rule_id) },
             model: Models::OkResult, **options)
      end

      # `POST /v1/split/config/get`.
      # @return [Oblodai::Models::SplitConfig]
      def get_config(**options)
        call("POST /v1/split/config/get", nil, model: Models::SplitConfig, **options)
      end

      # `POST /v1/split/config/set` — how long split shares are held back for refunds.
      # @return [Oblodai::Models::SplitConfig]
      def set_config(**params)
        options = Base.take_options!(params)
        call("POST /v1/split/config/set", params, model: Models::SplitConfig, **options)
      end

      # `POST /v1/split/recipient/optin/get` — whether this merchant accepts being a split recipient.
      # @return [Oblodai::Models::SplitOptIn]
      def get_opt_in(**options)
        call("POST /v1/split/recipient/optin/get", nil, model: Models::SplitOptIn, **options)
      end

      # `POST /v1/split/recipient/optin`.
      # @param enabled [Boolean]
      # @return [Oblodai::Models::SplitOptIn]
      def set_opt_in(enabled, **options)
        call("POST /v1/split/recipient/optin", { enabled: enabled }, model: Models::SplitOptIn, **options)
      end
    end
  end
end
