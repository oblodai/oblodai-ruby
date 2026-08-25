# frozen_string_literal: true

module Oblodai
  # Reading the core's status vocabularies without hard-coding string comparisons everywhere.
  module Status
    # Invoice statuses after which nothing else can happen.
    FINAL_PAYMENT_STATUSES = %w[paid paid_over wrong_amount expired cancelled].freeze
    # Payout statuses after which nothing else can happen.
    FINAL_PAYOUT_STATUSES = %w[confirmed failed cancelled].freeze

    module_function

    # @param status [String]
    # @return [Boolean]
    def payment_final?(status)
      FINAL_PAYMENT_STATUSES.include?(status)
    end

    # `paid` or `paid_over` — the merchant has the money. `wrong_amount` is NOT paid: resolve it.
    # @param status [String]
    # @return [Boolean]
    def payment_paid?(status)
      %w[paid paid_over].include?(status)
    end

    # The invoice is waiting for a merchant decision (underpaid): call `refunds.resolve`.
    # @param status [String]
    # @return [Boolean]
    def payment_underpaid?(status)
      status == "wrong_amount"
    end

    # @param status [String]
    # @return [Boolean]
    def payout_final?(status)
      FINAL_PAYOUT_STATUSES.include?(status)
    end

    # The payout reached the chain and is irreversible.
    # @param status [String]
    # @return [Boolean]
    def payout_succeeded?(status)
      status == "confirmed"
    end
  end
end
