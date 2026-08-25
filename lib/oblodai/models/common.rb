# frozen_string_literal: true

require_relative "model"

module Oblodai
  # Models shared by several namespaces. Amounts inside them are decimal strings rendered at the
  # asset's own scale ("10.000000" for USDT) — never floats; {Oblodai::Money} adds and compares them.
  module Models
    # Counters of a paged list result.
    class Paginate < Model
      # @return [Integer] total number of matching rows
      field :total
      # @return [Integer] page size the core applied
      field :per_page
      # @return [Integer] offset of this page
      field :offset
      # @return [Boolean] the core's own "there is more" flag; iteration stops on it
      field :has_pages
    end

    # Element of every batch listing (`/v1/payout/mass`, `/v1/payout/link/batch`, `/v1/batch/info`).
    class BatchElement < Model
      # @return [Integer] position of the element in the submitted array
      field :idx
      # @return [Boolean] whether this element succeeded
      field :ok, optional: true
      # @return [String, nil] your reference for the element
      field :order_id, optional: true
      # @return [Hash, nil] the created object, when the element succeeded
      field :result, optional: true
      # @return [String, nil] human explanation of the failure
      field :message, optional: true
      # @return [String, nil] machine code of the failure (`family.reason`)
      field :error_code, optional: true
      # @return [Integer, nil] HTTP status the element would have had on its own
      field :http_status, optional: true
      # @return [String, nil] per-element state inside an asynchronous batch
      field :status, optional: true
    end

    # `{ ok: true }` — the acknowledgement several routes answer with.
    class OkResult < Model
      # @return [Boolean]
      field :ok
    end
  end
end
