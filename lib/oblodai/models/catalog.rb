# frozen_string_literal: true

require_relative "common"

module Oblodai
  module Models
    # One network an asset lives on.
    class CurrencyNetwork < Model
      # @return [String]
      field :network
      # @return [String] native | token
      field :kind
      # @return [Integer] confirmations a deposit needs
      field :min_confirmations
      # @return [Boolean] deposits and payouts both possible right now
      field :available
      # @return [Boolean]
      field :deposit_available
      # @return [Boolean]
      field :payout_available
      # @return [Boolean] the network offered first on the pay page
      field :default_offer
      # @return [String, nil] token contract address, for tokens
      field :contract, optional: true
    end

    # One asset and the networks it settles on.
    class CurrencyInfo < Model
      # @return [String]
      field :currency
      # @return [Integer] on-chain scale of the asset
      field :decimals
      # @return [Array<Oblodai::Models::CurrencyNetwork>]
      field :networks, model: CurrencyNetwork, list: true
    end

    # A currency an invoice can be priced in.
    class PricingCurrency < Model
      # @return [String]
      field :currency
      # @return [Integer]
      field :decimals
      # @return [Boolean] true for the 23 fiats
      field :fiat
    end

    # `GET /v1/currencies` — every asset, its networks and live availability.
    class Currencies < Model
      # @return [Array<Oblodai::Models::CurrencyInfo>]
      field :currencies, model: CurrencyInfo, list: true
      # @return [Array<Oblodai::Models::PricingCurrency>]
      field :pricing_currencies, model: PricingCurrency, list: true
    end

    # `/v1/exchange-rate/list` item: 1 `from` = `course` `to`.
    class ExchangeRate < Model
      # @return [String]
      field :from
      # @return [String]
      field :to
      # @return [String] the rate, as a decimal string
      field :course
    end
  end
end
