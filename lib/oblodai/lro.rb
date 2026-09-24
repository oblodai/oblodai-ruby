# frozen_string_literal: true

module Oblodai
  # Which operations are long-running, and how to follow them — a decision of this SDK, not of the
  # API. A create call listed in {LRO} returns an {Oblodai::Job} instead of its bare
  # acknowledgement; `job.wait` polls the operation named here until the status is terminal. The
  # runtime applies it by the route's `operationId`; the generator knows nothing of this table.
  module LRO
    # `create operationId => poll operationId`.
    CREATES = {
      "createPaymentBatch" => "getBatchInfo",
      "createPayoutBatch" => "getBatchInfo",
      "createRefundBatch" => "getBatchInfo",
      "createTransferBatch" => "getBatchInfo",
      "createDocumentJob" => "getDocumentJob"
    }.freeze

    # How to follow one kind of job.
    #
    # @!attribute [r] id_field
    #   @return [String] the job's id in the create answer; sent under the same name to the poll
    #     (and to the download)
    # @!attribute [r] model
    #   @return [String] the generated model the poll answer parses to
    # @!attribute [r] download
    #   @return [String, nil] the `operationId` that returns the finished job's file
    Poll = Struct.new(:id_field, :model, :download, keyword_init: true) do
      def initialize(*)
        super
        freeze
      end
    end

    # `poll operationId => how to follow it`.
    POLLS = {
      "getBatchInfo" => Poll.new(id_field: "batch_id", model: "BatchInfoResponse"),
      "getDocumentJob" => Poll.new(id_field: "job_id", model: "DocumentJobView",
                                   download: "downloadDocumentJobFile")
    }.freeze

    # Statuses after which a job no longer changes: a batch ends `completed` or `stopped`
    # (`on_error=stop`), a document job `done`, `failed` or `expired`.
    TERMINAL_STATUSES = %w[completed stopped done failed expired].freeze
  end
end
