# frozen_string_literal: true

require_relative "base"
require_relative "../models/account"
require_relative "../models/payouts"

module Oblodai
  module Resources
    # Static deposit wallets: one permanent address per customer, deposits reported as `wallet.paid`.
    class Wallets < Base
      # `POST /v1/wallet` — a permanent deposit address for one customer. Idempotent by `order_id`.
      #
      # Codes worth branching on: `wallet.static_disabled`, `wallet.unsupported_network`,
      # `wallet.no_network` (multi-network asset, no `network` given), `wallet.no_address`
      # (derivation is temporarily unavailable — retryable), `wallet.sandbox_unsupported`,
      # `request.unknown_currency`, `idempotency.key_reused`.
      # @return [Oblodai::Models::Wallet]
      def create(**params)
        options = Base.take_options!(params)
        call("POST /v1/wallet", params, model: Models::Wallet, **options)
      end

      # `POST /v1/wallet/qr`.
      # @param address [String, Oblodai::Models::Wallet] the wallet, or its address
      # @return [Oblodai::Models::WalletQr]
      def qr(address, **options)
        call("POST /v1/wallet/qr", { address: id_of(address, :address) },
             model: Models::WalletQr, **options)
      end

      # `POST /v1/wallet/block` — stop crediting an address; later deposits wait for a refund decision.
      # @return [Oblodai::Models::WalletBlocked]
      def block(**params)
        options = Base.take_options!(params)
        call("POST /v1/wallet/block", params, model: Models::WalletBlocked, **options)
      end

      # `POST /v1/wallet/blocked-address-refund` — send funds that landed on a blocked address back.
      # Payout key.
      #
      # Codes worth branching on: `wallet.bad_uuid`, `refund.no_address` (the address is not
      # blocked), `refund.nothing_to_refund` (already refunded or empty), `refund.dust` (below the
      # network minimum), `refund.destination_internal`, `merchant.wrong_key_kind`.
      # @return [Oblodai::Models::Payout]
      def refund_blocked_deposit(**params)
        options = Base.take_options!(params)
        call("POST /v1/wallet/blocked-address-refund", params, model: Models::Payout, **options)
      end
    end
  end
end
