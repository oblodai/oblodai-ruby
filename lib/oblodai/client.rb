# frozen_string_literal: true

require_relative "config"
require_relative "core/transport"
require_relative "contract/routes"
require_relative "resources/account"
require_relative "resources/batches"
require_relative "resources/documents"
require_relative "resources/links"
require_relative "resources/payments"
require_relative "resources/payouts"
require_relative "resources/settings"
require_relative "resources/wallets"
require_relative "resources/webhooks"
require_relative "version"

module Oblodai
  # The Oblodai API client. One instance per API key; safe to share across threads (it holds no
  # per-request state; each call opens its own connection).
  #
  #     client = Oblodai::Client.new(public_id: "pk_live_…", secret: "…")
  #     invoice = client.payments.create(amount: "25", currency: "USDT", network: "tron",
  #                                      order_id: "o-1")
  #     invoice.url  # the hosted pay page
  #
  # Credentials fall back to `OBLODAI_PUBLIC_ID` / `OBLODAI_SECRET`, the base URL to
  # `OBLODAI_BASE_URL`.
  class Client
    # @return [Oblodai::Resources::Payments]
    attr_reader :payments
    # @return [Oblodai::Resources::Refunds]
    attr_reader :refunds
    # @return [Oblodai::Resources::Payouts]
    attr_reader :payouts
    # @return [Oblodai::Resources::PayoutLinks]
    attr_reader :payout_links
    # @return [Oblodai::Resources::PaymentLinks]
    attr_reader :payment_links
    # @return [Oblodai::Resources::Batches]
    attr_reader :batches
    # @return [Oblodai::Resources::Transfers]
    attr_reader :transfers
    # @return [Oblodai::Resources::Wallets]
    attr_reader :wallets
    # @return [Oblodai::Resources::Webhooks]
    attr_reader :webhooks
    # @return [Oblodai::Resources::Documents]
    attr_reader :documents
    # @return [Oblodai::Resources::Splits]
    attr_reader :splits
    # @return [Oblodai::Resources::Settings]
    attr_reader :settings
    # @return [Oblodai::Resources::Account]
    attr_reader :account
    # @return [Oblodai::Resources::Catalog]
    attr_reader :catalog
    # @return [Oblodai::Resources::Sandbox]
    attr_reader :sandbox
    # @return [Oblodai::Resources::Merchants]
    attr_reader :merchants
    # The transport, exposed for advanced use (custom routes, tests).
    # @return [Oblodai::Transport]
    attr_reader :transport
    # @return [Oblodai::Config]
    attr_reader :config

    # @see Oblodai::Config#initialize for every option and its environment fallback
    def initialize(**options)
      @config = options[:config] || Config.new(**options)
      @transport = Transport.new(
        base_url: @config.base_url, credentials: @config.credentials, http: @config.http,
        timeout_ms: @config.timeout_ms, deadline_ms: @config.deadline_ms,
        retry_policy: @config.retry_policy, logger: @config.logger,
        headers: @config.headers, admin_token: @config.admin_token,
        user_agent: self.class.user_agent
      )
      @payments = Resources::Payments.new(@transport)
      @refunds = Resources::Refunds.new(@transport)
      @payouts = Resources::Payouts.new(@transport)
      @payout_links = Resources::PayoutLinks.new(@transport)
      @payment_links = Resources::PaymentLinks.new(@transport)
      @batches = Resources::Batches.new(@transport)
      @transfers = Resources::Transfers.new(@transport)
      @wallets = Resources::Wallets.new(@transport)
      @webhooks = Resources::Webhooks.new(@transport)
      @documents = Resources::Documents.new(@transport)
      @splits = Resources::Splits.new(@transport)
      @settings = Resources::Settings.new(@transport)
      @account = Resources::Account.new(@transport)
      @catalog = Resources::Catalog.new(@transport)
      @sandbox = Resources::Sandbox.new(@transport)
      @merchants = Resources::Merchants.new(@transport)
    end

    # @return [String] what the SDK identifies itself as, contract hash included
    def self.user_agent
      "oblodai-ruby/#{VERSION} (contract #{Contract::CONTRACT_HASH[0, 12]}; ruby #{RUBY_VERSION})"
    end

    def inspect
      "#<Oblodai::Client base_url=#{@config.base_url.inspect} " \
        "credentials=#{@config.credentials ? "set" : "none"}>"
    end
  end
end
