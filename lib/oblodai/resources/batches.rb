# frozen_string_literal: true

require_relative "base"
require_relative "../models/payments"
require_relative "../models/payouts"

module Oblodai
  module Resources
    # Progress of asynchronous batches (payment, refund, payout, transfer, payout-link).
    class Batches < Base
      # `POST /v1/batch/info` — status, counters and per-row outcomes.
      #
      # Accepts either key kind; the core requires the kind that created the batch, so a payout
      # batch is retried once with the payout key when one is configured.
      #
      # @param batch_id [String]
      # @return [Oblodai::Models::BatchInfo]
      def info(batch_id, **options)
        call("POST /v1/batch/info", { batch_id: batch_id }, model: Models::BatchInfo, **options)
      rescue PermissionError => e
        raise e unless e.code == "merchant.wrong_key_kind" && !options[:prefer_payout_key]

        call("POST /v1/batch/info", { batch_id: batch_id }, model: Models::BatchInfo,
                                                            **options.merge(prefer_payout_key: true))
      end
      alias get info
    end

    # Internal, instant, fee-free moves between platform balances. Payout key.
    class Transfers < Base
      # `POST /v1/transfer/to-personal` — business balance → the owner's personal wallet
      # (needs an owner link).
      # @return [Oblodai::Models::TransferToPersonal]
      def to_personal(**params)
        options = Base.take_options!(params)
        call("POST /v1/transfer/to-personal", params, model: Models::TransferToPersonal, **options)
      end

      # `POST /v1/transfer/to-user` — business balance → another platform user's personal wallet.
      # `amount` and `currency` are required.
      # @return [Oblodai::Models::TransferToUser]
      def to_user(**params)
        options = Base.take_options!(params)
        call("POST /v1/transfer/to-user", params, model: Models::TransferToUser, **options)
      end

      # `POST /v1/transfer/batch` — ASYNCHRONOUS batch of {#to_user} transfers; poll `batches.info`.
      # `order_id` is required on every item.
      # @return [Oblodai::Models::BatchSubmitted]
      def batch(**params)
        options = Base.take_options!(params)
        call("POST /v1/transfer/batch", params, model: Models::BatchSubmitted, **options)
      end
    end
  end
end
