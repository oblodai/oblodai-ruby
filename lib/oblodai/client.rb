# frozen_string_literal: true

require_relative "config"
require_relative "core/transport"
require_relative "generated/resources"
require_relative "generated/facts"
require_relative "version"

module Oblodai
  # The Oblodai API client. One instance per API key; safe to share across threads (it holds no
  # per-request state; each call opens its own connection).
  #
  #     client = Oblodai::Client.new(public_id: "oblodai_…", secret: "…")
  #     invoice = client.payments.create(amount: "25", currency: "USDT", network: "tron",
  #                                      order_id: "o-1")
  #     invoice.url  # the hosted pay page
  #
  # Credentials fall back to `OBLODAI_PUBLIC_ID` / `OBLODAI_SECRET`, the base URL to
  # `OBLODAI_BASE_URL`, the admin token to `OBLODAI_ADMIN_TOKEN`.
  class Client
    # Resource namespaces: reader name => generated class name.
    RESOURCES = {
      payments: :Payments, payment_links: :PaymentLinks, refunds: :Refunds, payouts: :Payouts,
      payout_links: :PayoutLinks, batches: :Batches, splits: :Splits, wallets: :Wallets,
      account: :Account, webhooks: :Webhooks, settings: :Settings, api_allowlist: :ApiAllowlist,
      referrals: :Referrals, documents: :Documents, checkout: :Checkout, sandbox: :Sandbox,
      cli_login: :CliLogin
    }.freeze

    # @!attribute [r] payments
    #   @return [Oblodai::Resources::Payments]
    # @!attribute [r] payment_links
    #   @return [Oblodai::Resources::PaymentLinks]
    # @!attribute [r] refunds
    #   @return [Oblodai::Resources::Refunds]
    # @!attribute [r] payouts
    #   @return [Oblodai::Resources::Payouts]
    # @!attribute [r] payout_links
    #   @return [Oblodai::Resources::PayoutLinks]
    # @!attribute [r] batches
    #   @return [Oblodai::Resources::Batches]
    # @!attribute [r] splits
    #   @return [Oblodai::Resources::Splits]
    # @!attribute [r] wallets
    #   @return [Oblodai::Resources::Wallets]
    # @!attribute [r] account
    #   @return [Oblodai::Resources::Account]
    # @!attribute [r] webhooks
    #   @return [Oblodai::Resources::Webhooks]
    # @!attribute [r] settings
    #   @return [Oblodai::Resources::Settings]
    # @!attribute [r] api_allowlist
    #   @return [Oblodai::Resources::ApiAllowlist]
    # @!attribute [r] referrals
    #   @return [Oblodai::Resources::Referrals]
    # @!attribute [r] documents
    #   @return [Oblodai::Resources::Documents]
    # @!attribute [r] checkout
    #   @return [Oblodai::Resources::Checkout]
    # @!attribute [r] sandbox
    #   @return [Oblodai::Resources::Sandbox]
    # @!attribute [r] cli_login
    #   @return [Oblodai::Resources::CliLogin]
    attr_reader(*RESOURCES.keys)
    # The transport, exposed for advanced use (custom routes, tests).
    # @return [Oblodai::Transport]
    attr_reader :transport
    # @return [Oblodai::Config]
    attr_reader :config

    # @see Oblodai::Config#initialize for every option and its environment fallback
    def initialize(**options)
      @config = options[:config] || Config.new(**options)
      attach(Transport.new(
               base_url: @config.base_url, credentials: @config.credentials, http: @config.http,
               timeout: @config.timeout, deadline: @config.deadline,
               retry_policy: @config.retry_policy, logger: @config.logger,
               headers: @config.headers, admin_token: @config.admin_token,
               hooks: @config.hooks, user_agent: self.class.user_agent
             ))
    end

    # A new client with these overridden; the original is untouched, the HTTP adapter and the
    # learned clock offset are shared.
    #
    #     patient = client.with_options(timeout: 120, max_retries: 5)
    #
    # @param timeout [Numeric, nil] seconds per attempt
    # @param max_retries [Integer, nil] replaces the retry policy's `max_retries`
    # @param extra_headers [Hash, nil] merged over the client's `headers`
    # @return [Oblodai::Client]
    def with_options(timeout: nil, max_retries: nil, extra_headers: nil)
      clone = self.class.allocate
      clone.send(:attach, @transport.derive(timeout: timeout, max_retries: max_retries,
                                            extra_headers: extra_headers), @config)
      clone
    end

    # @return [String] what the SDK identifies itself as
    def self.user_agent
      "oblodai-ruby/#{VERSION} (ruby #{RUBY_VERSION})"
    end

    # @return [String]
    def base_url
      @transport.base_url
    end

    def inspect
      "#<Oblodai::Client base_url=#{base_url.inspect} " \
        "credentials=#{@config.credentials ? "set" : "none"}>"
    end

    private

    def attach(transport, config = @config)
      @config = config
      @transport = transport
      RESOURCES.each do |reader, klass|
        instance_variable_set(:"@#{reader}", Resources.const_get(klass, false).new(transport))
      end
    end
  end
end
