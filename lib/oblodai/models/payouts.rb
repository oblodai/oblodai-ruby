# frozen_string_literal: true

require_relative "common"

module Oblodai
  module Models
    # Payout as `/v1/payout`, `/info`, `/history`, `/cancel`, mass/batch elements and refunds render
    # it (core `PayoutResult`). `error`/`error_code` appear on `info` for failed payouts.
    class Payout < Model
      # @return [String] payout id
      field :uuid
      # @return [String, nil] merchant reference; null for refunds (keyed by `reference`/`refund_for`)
      field :order_id
      # @return [String] one of {Oblodai::Enums::PAYOUT_STATUSES}
      field :status
      # @return [Boolean] nothing else can happen to this payout
      field :is_final
      # @return [String] amount sent to the recipient
      field :amount
      # @return [String]
      field :currency
      # @return [String] settlement network
      field :network
      # @return [String] destination address
      field :address
      # @return [String] memo/destination tag, when the network needs one
      field :memo
      # @return [String] total debited from the balance (amount plus commission when the merchant bears the fee)
      field :payer_amount
      # @return [String] our commission
      field :commission
      # @return [String] who bore the network fee
      field :fee_bearer
      # @return [String] balance the payout was funded from: business | personal
      field :source
      # @return [Boolean] whether it waits for a manual approval
      field :approval_required
      # @return [Boolean] this payout is a refund
      field :is_refund
      # @return [String, nil] for refunds: the invoice being refunded
      field :refund_for
      # @return [String, nil] for refunds: the invoice's order_id
      field :payment_order_id
      # @return [String] transaction hash once broadcast
      field :txid
      # @return [String] signed link to the payout PDF
      field :document_url
      # @return [String]
      field :created_at
      # @return [String]
      field :updated_at
      # @return [String, nil] `info` on a failed payout: human explanation
      field :error, optional: true
      # @return [String, nil] `info` on a failed payout: machine code
      field :error_code, optional: true
      # @return [String, nil] set on refunds of blocked static-wallet deposits
      field :wallet_uuid, optional: true
      # @return [String, nil] `/v1/payment/resolve` with `action: "refund"`: "refunded"
      field :resolution, optional: true

      # @return [Boolean] the payout reached a final state
      def final?
        Oblodai::Status.payout_final?(status)
      end

      # @return [Boolean] the payout is on-chain and irreversible
      def succeeded?
        status == "confirmed"
      end
    end

    # Element of a synchronous payout batch (`/v1/payout/mass`).
    class PayoutBatchElement < BatchElement
      # @return [Oblodai::Models::Payout, nil]
      field :result, model: Payout, optional: true
    end

    # `/v1/payout/calculate`. Amounts are null when the asset cannot be priced right now.
    class PayoutCalculation < Model
      # @return [String, nil] what the recipient would get
      field :amount
      # @return [String]
      field :currency
      # @return [String]
      field :network
      # @return [String, nil]
      field :commission
      # @return [String, nil] what would be debited from the balance
      field :payer_amount
      # @return [String] who would bear the network fee
      field :fee_bearer
      # @return [String] pricing mode of the fee
      field :fee_type
    end

    # `/v1/payout/validate` — the dry run; errors are the same the create call would raise.
    class PayoutValidation < Model
      # @return [Boolean] the payout would be accepted
      field :valid
      # @return [String]
      field :amount
      # @return [String]
      field :currency
      # @return [String]
      field :network
      # @return [String]
      field :commission
      # @return [String]
      field :payer_amount
      # @return [String]
      field :fee_bearer
      # @return [String] non-empty when part of the balance is still maturing (reorg window)
      field :maturity_note
      # @return [String, nil] which balance would fund it, when reported
      field :funded_by, optional: true
    end

    # `/v1/transfer/to-personal`: business → the owner's personal balance.
    class TransferToPersonal < Model
      # @return [String]
      field :uuid
      # @return [String]
      field :currency
      # @return [String]
      field :amount
      # @return [String] "to_personal"
      field :direction
      # @return [String] personal balance after the transfer
      field :personal_balance
      # @return [String]
      field :document_url
    end

    # `/v1/transfer/to-user`: business → another platform user's personal balance.
    class TransferToUser < Model
      # @return [String]
      field :uuid
      # @return [String]
      field :currency
      # @return [String]
      field :amount
      # @return [String] the recipient
      field :to_user_id
      # @return [String]
      field :document_url
    end

    # `/v1/payout/fee-config/*` — who bears the network fee on payouts by default.
    class PayoutFeeConfig < Model
      # @return [Boolean] true: the recipient pays the network fee out of the amount
      field :fee_on_recipient
      # @return [Boolean] `get` only: whether the merchant ever set it
      field :configured, optional: true
    end

    # `/v1/payout/refund-fee-config/*` — who bears the fee on refunds.
    class RefundFeeConfig < Model
      # @return [Boolean] true: the customer pays the network fee out of the refund
      field :fee_on_customer
      # @return [Boolean] `get` only
      field :configured, optional: true
    end

    # `/v1/payment/fee-config/*` — share of the network fee charged to the payer.
    class PaymentFeeConfig < Model
      # @return [Integer] 0–100
      field :payer_pays_percent
      # @return [Boolean] `get` only
      field :enabled, optional: true
    end
  end
end
