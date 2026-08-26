# frozen_string_literal: true

require "uri"
require_relative "core/logger"
require_relative "core/request"
require_relative "core/retry"
require_relative "errors"

module Oblodai
  DEFAULT_BASE_URL = "https://api.oblodai.com"

  # Merges explicit options with the environment and validates what can be validated up front.
  # Every option falls back to an `OBLODAI_*` environment variable, so a deployment can configure
  # the SDK without touching code.
  class Config
    # @return [String]
    attr_reader :base_url
    # @return [Oblodai::RequestBuilder::Credentials, nil]
    attr_reader :credentials
    # @return [Oblodai::RequestBuilder::Credentials, nil]
    attr_reader :payout_credentials
    # @return [Object, nil]
    attr_reader :http
    # @return [Integer]
    attr_reader :timeout_ms
    # @return [Integer]
    attr_reader :deadline_ms
    # @return [Oblodai::RetryPolicy]
    attr_reader :retry_policy
    # @return [Object]
    attr_reader :logger
    # @return [Hash]
    attr_reader :headers
    # @return [String, nil]
    attr_reader :admin_token

    # @param public_id [String, nil] public id of the API key (`X-Public-Id`); env OBLODAI_PUBLIC_ID
    # @param secret [String, nil] secret of the API key; env OBLODAI_SECRET
    # @param payout_public_id [String, nil] optional dedicated payout key; env OBLODAI_PAYOUT_PUBLIC_ID
    # @param payout_secret [String, nil] env OBLODAI_PAYOUT_SECRET
    # @param base_url [String, nil] API origin; env OBLODAI_BASE_URL, then https://api.oblodai.com
    # @param http [#call, nil] HTTP adapter (a fake in tests, a proxy-aware Net::HTTP in production)
    # @param timeout_ms [Integer] per-attempt timeout
    # @param deadline_ms [Integer] overall budget per call including retries
    # @param retry_policy [Hash, Oblodai::RetryPolicy] overrides for {Oblodai::RetryPolicy}
    #   (`{ max_retries: 0 }` disables retries), or a policy object
    # @param logger [Object, nil] anything with debug/info/warn/error(message, fields);
    #   `OBLODAI_LOG=debug` enables a stderr logger when omitted
    # @param headers [Hash] extra headers on every request
    # @param admin_token [String, nil] admin token of a self-hosted gateway; sent as `X-Admin-Token`
    #   on the two merchant-provisioning routes and nowhere else. env OBLODAI_ADMIN_TOKEN
    # @param allow_insecure_base_url [Boolean] permit plain http:// base URLs; env OBLODAI_ALLOW_INSECURE=1
    # @param env [Hash] the environment to read fallbacks from
    def initialize(public_id: nil, secret: nil, payout_public_id: nil, payout_secret: nil,
                   base_url: nil, http: nil, timeout_ms: 30_000, deadline_ms: 90_000,
                   retry_policy: {}, logger: nil, headers: {}, admin_token: nil,
                   allow_insecure_base_url: false, env: ENV)
      # A blank value is not a base URL: an `export OBLODAI_BASE_URL=` in a shell profile arrives as
      # "" and must fall through to the next source, exactly as a blank credential does.
      @base_url = [base_url, env["OBLODAI_BASE_URL"], DEFAULT_BASE_URL]
                  .find { |value| !value.nil? && !value.to_s.strip.empty? }
                  .to_s.strip.sub(%r{/+\z}, "")
      assert_base_url!(@base_url, allow_insecure_base_url || env["OBLODAI_ALLOW_INSECURE"] == "1")

      @credentials = key_pair(public_id || env["OBLODAI_PUBLIC_ID"], secret || env["OBLODAI_SECRET"],
                              "public_id and secret must be provided together " \
                              "(or set both OBLODAI_PUBLIC_ID and OBLODAI_SECRET)")
      @payout_credentials = key_pair(payout_public_id || env["OBLODAI_PAYOUT_PUBLIC_ID"],
                                     payout_secret || env["OBLODAI_PAYOUT_SECRET"],
                                     "payout_public_id and payout_secret must be provided together")
      @http = http
      @timeout_ms = timeout_ms
      @deadline_ms = deadline_ms
      @retry_policy = retry_policy.is_a?(RetryPolicy) ? retry_policy : RetryPolicy.new.with(**(retry_policy || {}))
      @logger = logger || logger_from(env)
      @headers = headers || {}
      @admin_token = admin_token || env["OBLODAI_ADMIN_TOKEN"]
    end

    # What the client is pointed at — never how it proves who it is.
    def inspect
      "#<Oblodai::Config base_url=#{@base_url.inspect} " \
        "credentials=#{@credentials ? "#{@credentials.public_id} (secret [redacted])" : "none"} " \
        "payout_credentials=#{@payout_credentials ? "#{@payout_credentials.public_id} (secret [redacted])" : "none"} " \
        "admin_token=#{@admin_token ? "[redacted]" : "none"} " \
        "timeout_ms=#{@timeout_ms} deadline_ms=#{@deadline_ms}>"
    end
    alias to_s inspect

    private

    # Half a key pair is always a configuration mistake: the SDK would sign with a secret the
    # gateway cannot match, or send an id it cannot verify. An empty string is not a credential
    # either — an unset `OBLODAI_SECRET=` in a shell profile arrives as "" and would otherwise be
    # signed with, producing an unexplainable 401 instead of the missing-credentials error.
    # @return [Oblodai::RequestBuilder::Credentials, nil]
    def key_pair(public_id, secret, message)
      public_id = nil if public_id.nil? || public_id.to_s.strip.empty?
      secret = nil if secret.nil? || secret.to_s.strip.empty?
      return nil if public_id.nil? && secret.nil?
      raise ConfigError.new("sdk.bad_config", message) if public_id.nil? || secret.nil?

      RequestBuilder::Credentials.new(public_id: public_id, secret: secret)
    end

    def logger_from(env)
      level = env["OBLODAI_LOG"].to_s.downcase
      return NullLogger.new unless IOLogger::LEVELS.key?(level.to_sym)

      IOLogger.new(level.to_sym)
    end

    def assert_base_url!(base_url, allow_insecure)
      uri = begin
        URI.parse(base_url)
      rescue URI::InvalidURIError
        raise ConfigError.new("sdk.bad_config", "base_url is not a valid URL: #{base_url}", "base_url")
      end
      # URI.parse accepts "api.oblodai.com" and "/v1" happily, with no scheme and no host; the SDK
      # would then build "://" URLs and fail deep inside the HTTP library.
      if uri.scheme.nil? || uri.host.nil? || uri.host.empty?
        raise ConfigError.new(
          "sdk.bad_config",
          "base_url must be an absolute URL with a scheme and a host (got #{base_url.inspect})",
          "base_url"
        )
      end
      return if uri.scheme == "https"

      local = ["localhost", "127.0.0.1", "[::1]", "::1"].include?(uri.host)
      return if uri.scheme == "http" && (allow_insecure || local)

      raise ConfigError.new(
        "sdk.bad_config",
        "base_url must use https (got #{uri.scheme}://#{uri.host}); " \
        "set allow_insecure_base_url: true for a local core",
        "base_url"
      )
    end
  end
end
