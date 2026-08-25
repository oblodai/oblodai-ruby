# frozen_string_literal: true

require_relative "base"
require_relative "../models/account"

module Oblodai
  module Resources
    # Generated PDF/CSV documents. Every method returns the bytes ({Oblodai::FileResult}); large
    # ranges go through asynchronous jobs ({#create_job} → {#job_info} → {#job_file}). Payment key.
    #
    # Query options common to the reports: `lang:` (a 2-letter code, 41 supported), `format:`
    # ("pdf" or "csv" where the document offers both) and `from:`/`to:` (`YYYY-MM-DD`).
    class Documents < Base
      # `POST /v1/documents/jobs` — queue a large report; poll {#job_info}, then {#job_file}.
      # @return [Oblodai::Models::DocumentJob]
      def create_job(**params)
        options = Base.take_options!(params)
        call("POST /v1/documents/jobs", params, model: Models::DocumentJob, **options)
      end

      # `POST /v1/documents/jobs/info`.
      # @param job_id [String]
      # @return [Oblodai::Models::DocumentJob]
      def job_info(job_id, **options)
        call("POST /v1/documents/jobs/info", { job_id: job_id }, model: Models::DocumentJob, **options)
      end

      # `GET /v1/documents/jobs/file` — the finished job's bytes.
      # @return [Oblodai::FileResult]
      def job_file(job_id, **options)
        file("GET /v1/documents/jobs/file", query: { job_id: job_id }, **options)
      end

      # `GET /v1/documents/statement` — account statement for a period (PDF or CSV).
      # @return [Oblodai::FileResult]
      def statement(**query)
        options = Base.take_options!(query)
        file("GET /v1/documents/statement", query: query, **options)
      end

      # `GET /v1/documents/balance` — balance certificate (PDF).
      # @return [Oblodai::FileResult]
      def balance_certificate(**query)
        options = Base.take_options!(query)
        file("GET /v1/documents/balance", query: query, **options)
      end

      # `GET /v1/documents/fees` — the fee schedule in force for the merchant (PDF).
      # @return [Oblodai::FileResult]
      def fee_schedule(**query)
        options = Base.take_options!(query)
        file("GET /v1/documents/fees", query: query, **options)
      end

      # `GET /v1/documents/ledger` — full ledger export for a period (PDF or CSV).
      # @return [Oblodai::FileResult]
      def ledger(**query)
        options = Base.take_options!(query)
        file("GET /v1/documents/ledger", query: query, **options)
      end

      # `GET /v1/documents/split` — how one payment was split between partners (PDF).
      # @param payment_uuid [String]
      # @return [Oblodai::FileResult]
      def split_report(payment_uuid, **query)
        options = Base.take_options!(query)
        file("GET /v1/documents/split", query: query.merge(uuid: payment_uuid), **options)
      end

      # `GET /v1/documents/batch` — per-row report of an asynchronous batch.
      # @param batch_id [String]
      # @return [Oblodai::FileResult]
      def batch_report(batch_id, **query)
        options = Base.take_options!(query)
        file("GET /v1/documents/batch", query: query.merge(uuid: batch_id), **options)
      end

      # `GET /v1/documents/link` — payment-link report (its invoices).
      # @param link_id [String]
      # @return [Oblodai::FileResult]
      def link_report(link_id, **query)
        options = Base.take_options!(query)
        file("GET /v1/documents/link", query: query.merge(uuid: link_id), **options)
      end

      # `GET /v1/documents/wallet/statement` — static-wallet statement.
      # @param wallet_uuid [String]
      # @return [Oblodai::FileResult]
      def wallet_statement(wallet_uuid, **query)
        options = Base.take_options!(query)
        file("GET /v1/documents/wallet/statement", query: query.merge(uuid: wallet_uuid), **options)
      end

      # `GET /v1/documents/referrals` — referral earnings report.
      # @return [Oblodai::FileResult]
      def referrals_report(**query)
        options = Base.take_options!(query)
        file("GET /v1/documents/referrals", query: query, **options)
      end

      # `GET /v1/documents/{kind}/{id}` — a public document by its signed link (`exp` and `sig` come
      # from a `document_url`). No credentials needed; prefer fetching `document_url` directly.
      #
      # @param kind [String]
      # @param id [String]
      # @param exp [Integer] from the signed link
      # @param sig [String] from the signed link
      # @return [Oblodai::FileResult]
      def download(kind, id, exp:, sig:, **query)
        options = Base.take_options!(query)
        file("GET /v1/documents/{kind}/{id}", path_params: { kind: kind, id: id },
                                              query: query.merge(exp: exp, sig: sig), **options)
      end
    end
  end
end
