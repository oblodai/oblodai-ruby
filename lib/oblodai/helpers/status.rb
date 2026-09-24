# frozen_string_literal: true

require_relative "../generated/enums"

module Oblodai
  # Reading the core's status vocabularies without hard-coding string comparisons everywhere. The
  # classes of statuses come from the contract (`x-status-classes`), generated into
  # {Oblodai::Enums::PaymentStatus} and {Oblodai::Enums::PayoutStatus}.
  module Status
    # Invoice statuses after which nothing else can happen.
    FINAL_PAYMENT_STATUSES = Enums::PaymentStatus::FINAL
    # Payout statuses after which nothing else can happen.
    FINAL_PAYOUT_STATUSES = Enums::PayoutStatus::FINAL

    module_function

    # @param status [String]
    # @return [Boolean]
    def payment_final?(status)
      Enums::PaymentStatus.final?(status)
    end

    # `paid` or `paid_over` — the merchant has the money. `wrong_amount` is NOT paid: resolve it.
    # @param status [String]
    # @return [Boolean]
    def payment_paid?(status)
      Enums::PaymentStatus.success?(status)
    end

    # The invoice is waiting for a merchant decision (underpaid): call `payments.resolve`.
    # @param status [String]
    # @return [Boolean]
    def payment_underpaid?(status)
      status == Enums::PaymentStatus::WRONG_AMOUNT
    end

    # @param status [String]
    # @return [Boolean]
    def payout_final?(status)
      Enums::PayoutStatus.final?(status)
    end

    # The payout reached the chain and is irreversible.
    # @param status [String]
    # @return [Boolean]
    def payout_succeeded?(status)
      Enums::PayoutStatus.success?(status)
    end
  end
end
