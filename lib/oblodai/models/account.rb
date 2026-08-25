# frozen_string_literal: true

require_relative "common"

module Oblodai
  module Models
    # One asset's available balance.
    class BalanceEntry < Model
      # @return [String]
      field :currency
      # @return [String] available (spendable) balance
      field :balance
    end

    # `/v1/balance` — available balance per currency.
    class Balance < Model
      # @return [Hash] `{ "merchant" => [BalanceEntry, …] }`
      field :balance

      def after_initialize
        raw = self[:balance]
        @merchant = (raw.is_a?(Hash) ? BalanceEntry.from_list(raw["merchant"] || raw[:merchant]) : []).freeze
      end

      # The merchant's business balances, decoded.
      # @return [Array<Oblodai::Models::BalanceEntry>]
      attr_reader :merchant

      # @param currency [String]
      # @return [String, nil] the available balance of one asset
      def available(currency)
        @merchant.find { |entry| entry.currency == currency }&.balance
      end
    end

    # Referral earnings of the last seven days.
    class ReferralWeek < Model
      # @return [Integer]
      field :referred_count
      # @return [Hash{String => String}]
      field :earnings_by_asset
    end

    # `/v1/referral/info`.
    class ReferralInfo < Model
      # @return [String] the merchant's referral code
      field :code
      # @return [String] ready-made invite link
      field :link
      # @return [Array<Integer>] referral tiers, basis points
      field :tier_bps
      # @return [Integer]
      field :referred_count
      # @return [Hash{String => String}] lifetime earnings per asset
      field :earnings_by_asset
      # @return [Oblodai::Models::ReferralWeek]
      field :week, model: ReferralWeek
    end

    # `/v1/vrcs` — volatility risk control (auto-convert volatile deposits to USDT).
    class VrcsStatus < Model
      # @return [Boolean]
      field :enabled
    end

    # Static (permanent) deposit wallet — `/v1/wallet`.
    class Wallet < Model
      # @return [String]
      field :uuid
      # @return [String] the permanent address
      field :address
      # @return [String]
      field :network
      # @return [String]
      field :currency
      # @return [String] your reference (the wallet is idempotent by it)
      field :order_id
      # @return [String] hosted page showing the address and QR
      field :url
      # @return [String]
      field :document_url
      # @return [String, nil] XRP destination tag, when the network needs one
      field :destination_tag, optional: true
      # @return [String, nil] TON/Stellar memo, when the network needs one
      field :memo, optional: true
      # @return [String, nil] XRP X-address
      field :address_xaddress, optional: true
      # @return [String, nil] XLM muxed address
      field :address_muxed, optional: true
    end

    # `/v1/wallet/block`.
    class WalletBlocked < Model
      # @return [String]
      field :uuid
      # @return [String]
      field :address
      # @return [Boolean]
      field :blocked
    end

    # `/v1/wallet/qr` — the address QR as a data URI.
    class WalletQr < Model
      # @return [String] `data:image/png;base64,…`
      field :image
    end

    # `/v1/auto-withdraw/*` entry: sweep an asset to an address once the balance passes `min_amount`.
    class AutoWithdrawRule < Model
      # @return [String]
      field :currency
      # @return [String]
      field :network
      # @return [String] destination
      field :address
      # @return [String] threshold
      field :min_amount
    end

    # `/v1/api-allowlist/*` — source IPs allowed to use the API keys; entries are CIDRs.
    class ApiAllowlist < Model
      # @return [Boolean] whether the list is enforced
      field :enabled
      # @return [Array<String>]
      field :items
    end

    # `/v1/payment/discount/*` — payer-facing discount or markup per currency+network.
    class DiscountRule < Model
      # @return [String]
      field :currency
      # @return [String]
      field :network
      # @return [Numeric] positive = discount for the payer, negative = markup
      field :discount_percent
    end

    # `/v1/payment/accuracy/*` — under/overpayment tolerance.
    class AccuracyConfig < Model
      # @return [Boolean]
      field :enabled
      # @return [Numeric] 0–5 %
      field :accuracy_percent
    end

    # `/v1/payment/autorefund/*` — refund over/underpayments automatically.
    class AutoRefundConfig < Model
      # @return [Boolean]
      field :overpay
      # @return [Boolean]
      field :underpay
      # @return [Boolean] `get` only: whether the merchant ever set it
      field :configured, optional: true
    end

    # `/v1/payment/accepted/*` — which currency/network pairs invoices may be paid in.
    class AcceptedMethod < Model
      # @return [String]
      field :currency
      # @return [String]
      field :network
      # @return [Boolean]
      field :available
      # @return [String, nil] why it is unavailable, when it is
      field :reason, optional: true
    end

    # `/v1/split/rule` and `/v1/split/rule/list` items: a share of every payment forwarded to a partner.
    class SplitRule < Model
      # @return [String]
      field :rule_id
      # @return [String] share of every payment, percent, as a decimal string
      field :percent
      # @return [Boolean]
      field :active
      # @return [String] external recipient address
      field :address
      # @return [String]
      field :network
      # @return [String]
      field :note
      # @return [Boolean] whether the share is reversed when the payment is refunded
      field :reversible
      # @return [String, nil] set for on-platform partner rules
      field :merchant_id, optional: true
    end

    # `/v1/split/config/*` — how long split shares are held back for refunds.
    class SplitConfig < Model
      # @return [Integer]
      field :refund_hold_seconds
    end

    # `/v1/split/recipient/optin*` — whether this merchant accepts being a split recipient.
    class SplitOptIn < Model
      # @return [Boolean]
      field :enabled
    end

    # Period a document covers.
    class DocumentPeriod < Model
      # @return [String] `YYYY-MM-DD`
      field :from
      # @return [String] `YYYY-MM-DD`
      field :to
    end

    # The finished file of an asynchronous document job.
    class DocumentJobFile < Model
      # @return [String] signed link (or use `documents.job_file`)
      field :download_url
      # @return [String] when the link stops working
      field :expires_at
      # @return [Integer]
      field :rows
      # @return [Integer]
      field :size_bytes
    end

    # `/v1/documents/jobs` and `/jobs/info` — a large report rendered in the background.
    class DocumentJob < Model
      # @return [String]
      field :job_id
      # @return [String] what is being rendered (statement, ledger, …)
      field :kind
      # @return [String] pdf | csv
      field :format
      # @return [String] 2-letter language code
      field :lang
      # @return [String] queued | processing | done | failed
      field :status
      # @return [Oblodai::Models::DocumentPeriod]
      field :period, model: DocumentPeriod
      # @return [String]
      field :created_at
      # @return [String]
      field :updated_at
      # @return [String, nil] human hint while queued (e.g. "15s")
      field :ready_within, optional: true
      # @return [Oblodai::Models::DocumentJobFile, nil] set once done
      field :file, model: DocumentJobFile, optional: true
      # @return [String, nil] why it failed
      field :error, optional: true

      # @return [Boolean]
      def done?
        status == "done"
      end
    end
  end
end
