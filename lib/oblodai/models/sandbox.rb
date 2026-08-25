# frozen_string_literal: true

require_relative "common"

module Oblodai
  module Models
    # `/v1/sandbox/faucet` — test funds credited to the dev store.
    class FaucetResult < Model
      # @return [String]
      field :asset
      # @return [String] how much was credited
      field :amount
      # @return [String] ledger entry the credit was booked as
      field :journal_id
    end

    # `/v1/sandbox/deposit` — a simulated on-chain deposit.
    class SandboxDeposit < Model
      # @return [String] the invoice it was attributed to
      field :invoice_id
      # @return [String]
      field :amount
      # @return [Integer] confirmations after this call
      field :confirmations
      # @return [String] the synthetic transaction hash
      field :txid
    end

    # `/v1/sandbox/reset`.
    class SandboxReset < Model
      # @return [Integer]
      field :invoices_cancelled
      # @return [Integer]
      field :balances_zeroed
    end

    # `/v1/sandbox/webhooks/replay`.
    class SandboxReplay < Model
      # @return [Boolean]
      field :ok
      # @return [String]
      field :delivery_id
    end
  end
end
