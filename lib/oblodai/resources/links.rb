# frozen_string_literal: true

require_relative "base"
require_relative "../models/links"
require_relative "../models/payments"

module Oblodai
  module Resources
    # Payout links (cheques): funds reserved now, claimed later by whoever holds the token.
    # Payout key.
    class PayoutLinks < Base
      # `POST /v1/payout/link` — reserve funds and mint a claim token (`claim_token`/`claim_url` are
      # returned once). Idempotent by `reference`.
      # @return [Oblodai::Models::PayoutLink]
      def create(**params)
        options = Base.take_options!(params)
        call("POST /v1/payout/link", params, model: Models::PayoutLink, **options)
      end

      # `POST /v1/payout/link/info`.
      # @param link_id [String]
      # @return [Oblodai::Models::PayoutLink]
      def info(link_id, **options)
        call("POST /v1/payout/link/info", { link_id: link_id }, model: Models::PayoutLink, **options)
      end
      alias get info

      # `POST /v1/payout/link/list`.
      # @return [Oblodai::Page<Oblodai::Models::PayoutLink>]
      def list(**params)
        options = Base.take_options!(params)
        page("POST /v1/payout/link/list", model: Models::PayoutLink, params: params, **options)
      end

      # `POST /v1/payout/link/cancel` — release the reserved funds of an unclaimed link.
      # @return [Oblodai::Models::PayoutLink]
      def cancel(link_id, **options)
        call("POST /v1/payout/link/cancel", { link_id: link_id }, model: Models::PayoutLink, **options)
      end

      # `POST /v1/payout/link/batch` — SYNCHRONOUS: many links in one signed call, per-element
      # outcomes. `reference` is required on every item.
      # @return [Array<Oblodai::Models::PayoutLinkBatchElement>]
      def batch(**params)
        options = Base.take_options!(params)
        plain_list("POST /v1/payout/link/batch", params, model: Models::PayoutLinkBatchElement, **options)
      end

      # `POST /v1/payout/link/cheque` — printable PDF cheque for a claim token.
      # @return [Oblodai::FileResult]
      def cheque(**params)
        options = Base.take_options!(params)
        file("POST /v1/payout/link/cheque", body: params, **options)
      end

      # --- recipient side (public, unsigned) ---

      # `GET /v1/claim/{token}` — what the recipient sees before claiming. No credentials needed.
      # @return [Oblodai::Models::ClaimPreview]
      def claim_preview(token, **options)
        call("GET /v1/claim/{token}", nil, model: Models::ClaimPreview,
                                           path_params: { token: token }, **options)
      end

      # `POST /v1/claim/{token}` — claim to an address (and passcode when the link has one).
      # No credentials needed.
      # @return [Oblodai::Models::ClaimResult]
      def claim(token, **params)
        options = Base.take_options!(params)
        call("POST /v1/claim/{token}", params, model: Models::ClaimResult,
                                               path_params: { token: token }, **options)
      end
    end

    # Reusable payment links (tip jars, price tags): each checkout spawns an invoice. Payment key.
    class PaymentLinks < Base
      # `POST /v1/payment/link`.
      # @return [Oblodai::Models::PaymentLinkCreated]
      def create(**params)
        options = Base.take_options!(params)
        call("POST /v1/payment/link", params, model: Models::PaymentLinkCreated, **options)
      end

      # `POST /v1/payment/link/info` — the link plus a page of the invoices it spawned (`payments`).
      # @param link_id [String]
      # @param limit [Integer, nil]
      # @param offset [Integer, nil]
      # @return [Oblodai::Models::PaymentLink]
      def info(link_id, limit: nil, offset: nil, **options)
        body = { link_id: link_id, limit: limit, offset: offset }.compact
        call("POST /v1/payment/link/info", body, model: Models::PaymentLink, **options)
      end
      alias get info

      # `POST /v1/payment/link/list`.
      # @return [Oblodai::Page<Oblodai::Models::PaymentLink>]
      def list(**params)
        options = Base.take_options!(params)
        page("POST /v1/payment/link/list", model: Models::PaymentLink, params: params, **options)
      end

      # `POST /v1/payment/link/toggle` — enable or disable a link.
      # @return [Oblodai::Models::PaymentLinkToggled]
      def toggle(link_id, active, **options)
        call("POST /v1/payment/link/toggle", { link_id: link_id, active: active },
             model: Models::PaymentLinkToggled, **options)
      end

      # --- payer side (public, unsigned) ---

      # `GET /v1/link/{id}` — the link as the payer sees it. No credentials needed.
      # @return [Oblodai::Models::PublicPaymentLink]
      def public_view(link_id, **options)
        call("GET /v1/link/{id}", nil, model: Models::PublicPaymentLink,
                                       path_params: { id: link_id }, **options)
      end

      # `POST /v1/link/{id}/checkout` — spawn an invoice from the link (rate-capped per IP).
      # No credentials needed.
      # @return [Oblodai::Models::PublicPayment]
      def checkout(link_id, **params)
        options = Base.take_options!(params)
        call("POST /v1/link/{id}/checkout", params, model: Models::PublicPayment,
                                                    path_params: { id: link_id }, **options)
      end
    end
  end
end
