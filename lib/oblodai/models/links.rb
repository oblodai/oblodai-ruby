# frozen_string_literal: true

require_relative "common"

module Oblodai
  module Models
    # Payout link (cheque) as `/v1/payout/link`, `/info`, `/list`, `/cancel` and batch elements
    # render it. Funds are reserved at creation and paid out when the holder claims the token.
    class PayoutLink < Model
      # @return [String] link id
      field :link_id
      # @return [String] one of {Oblodai::Enums::PAYOUT_LINK_STATUSES}
      field :status
      # @return [String] amount the recipient claims
      field :amount
      # @return [String]
      field :currency
      # @return [String]
      field :network
      # @return [String, nil] null while the asset cannot be priced
      field :commission
      # @return [String, nil] total reserved from the balance
      field :payer_amount
      # @return [String] who bears the network fee
      field :fee_bearer
      # @return [String] pricing mode of the fee
      field :fee_type
      # @return [String] your reference (the link is idempotent by it)
      field :reference
      # @return [String] shown to the recipient
      field :title
      # @return [String] shown to the recipient
      field :note
      # @return [Boolean] a passcode is required to claim
      field :passcode_protected
      # @return [String] when the reservation is released
      field :expires_at
      # @return [String]
      field :created_at
      # @return [String, nil] create and batch-create only — the secret the recipient claims with
      field :claim_token, optional: true
      # @return [String, nil] create only — the ready-made claim URL
      field :claim_url, optional: true
      # @return [String, nil] batch-create only — the batch this link belongs to
      field :batch_id, optional: true
      # @return [String, nil] set once claimed: the payout that paid the recipient
      field :payout_id, optional: true
      # @return [String, nil] set once claimed: where it went
      field :claim_address, optional: true
      # @return [String, nil] recipient email, when the link was emailed
      field :email, optional: true
      # @return [String, nil] the generated passcode, shown once on create when `passcode: "auto"`
      field :passcode, optional: true
    end

    # Element of a synchronous payout-link batch (`/v1/payout/link/batch`).
    class PayoutLinkBatchElement < BatchElement
      # @return [Oblodai::Models::PayoutLink, nil]
      field :result, model: PayoutLink, optional: true
    end

    # `GET /v1/claim/{token}` — what the recipient sees before claiming.
    class ClaimPreview < Model
      # @return [String]
      field :status
      # @return [Boolean] whether claiming would succeed right now
      field :claimable
      # @return [String]
      field :amount
      # @return [String]
      field :currency
      # @return [String]
      field :network
      # @return [String, nil]
      field :commission
      # @return [String, nil]
      field :payer_amount
      # @return [String]
      field :fee_bearer
      # @return [String]
      field :fee_type
      # @return [String]
      field :title
      # @return [String]
      field :note
      # @return [String]
      field :expires_at
    end

    # `POST /v1/claim/{token}` — the payout minted by a claim.
    class ClaimResult < Model
      # @return [String] the payout that pays the recipient (`payouts.info(uuid: payout_id)`)
      field :payout_id
      # @return [String]
      field :status
      # @return [String] where it was sent
      field :address
      # @return [String]
      field :amount
      # @return [String]
      field :currency
      # @return [String]
      field :network
      # @return [String, nil]
      field :commission
      # @return [String, nil]
      field :payer_amount
      # @return [String]
      field :fee_bearer
      # @return [String]
      field :fee_type
    end

    # One invoice spawned by a payment link.
    class PaymentLinkPayment < Model
      # @return [String]
      field :uuid
      # @return [String, nil]
      field :order_id, optional: true
      # @return [String]
      field :amount
      # @return [String]
      field :currency
      # @return [String]
      field :status
      # @return [String]
      field :created_at
    end

    # Payment link as `/v1/payment/link/info` and `/list` render it. Which amount fields are present
    # depends on `amount_mode`: `fixed` carries `amount_fixed`, `range` carries `min_amount`/`max_amount`.
    class PaymentLink < Model
      # @return [String]
      field :link_id
      # @return [String] the hosted page
      field :url
      # @return [Boolean] whether checkouts are accepted
      field :active
      # @return [String]
      field :title
      # @return [String]
      field :description
      # @return [String] fixed | open | range
      field :amount_mode
      # @return [String]
      field :currency
      # @return [String] `fixed` links
      field :amount_fixed
      # @return [String] network the invoices are pinned to
      field :pinned_network
      # @return [String] when the link stops working
      field :expires_at
      # @return [String]
      field :document_url
      # @return [String]
      field :created_at
      # @return [String, nil] `range` links
      field :min_amount, optional: true
      # @return [String, nil] `range` links
      field :max_amount, optional: true
      # @return [String, nil] asset the invoices are pinned to
      field :pinned_currency, optional: true
      # @return [Array<Oblodai::Models::PaymentLinkPayment>, nil] `info` only
      field :payments, model: PaymentLinkPayment, list: true, optional: true
    end

    # `POST /v1/payment/link` acknowledgement.
    class PaymentLinkCreated < Model
      # @return [String]
      field :link_id
      # @return [String] the hosted page
      field :url
      # @return [String]
      field :document_url
    end

    # `POST /v1/payment/link/toggle`.
    class PaymentLinkToggled < Model
      # @return [String]
      field :link_id
      # @return [Boolean]
      field :active
    end

    # `GET /v1/link/{id}` — the payer-facing view of a payment link.
    class PublicPaymentLink < Model
      # @return [String]
      field :link_id
      # @return [String]
      field :title
      # @return [String]
      field :description
      # @return [String] fixed | open | range
      field :amount_mode
      # @return [String]
      field :currency
      # @return [String] `fixed` links
      field :amount_fixed
      # @return [String]
      field :pinned_network
      # @return [String, nil] `range` links
      field :min_amount, optional: true
      # @return [String, nil] `range` links
      field :max_amount, optional: true
      # @return [String, nil]
      field :pinned_currency, optional: true
    end
  end
end
