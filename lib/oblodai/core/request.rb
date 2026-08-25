# frozen_string_literal: true

require "json"
require "uri"
require_relative "signing"
require_relative "../errors"

module Oblodai
  # Builds the outgoing request — URL, headers, body — as a pure function of its inputs, so the
  # signing material (what is signed) and the wire bytes (what is sent) come from one place and
  # cannot disagree. Nothing here touches the network or the clock.
  module RequestBuilder
    # Credentials of one key pair.
    Credentials = Struct.new(:public_id, :secret, keyword_init: true)

    # A request ready to hand to an HTTP adapter.
    #
    # @!attribute [r] request_uri
    #   @return [String] what was signed (path + query); kept for debugging signature mismatches
    Built = Struct.new(:url, :method, :headers, :body, :request_uri, keyword_init: true)

    # Headers the SDK owns; a caller-supplied header with one of these names is dropped.
    RESERVED_HEADERS = [
      Signing::HEADER_PUBLIC_ID, Signing::HEADER_SIGNATURE, Signing::HEADER_TIMESTAMP,
      Signing::HEADER_IDEMPOTENCY_KEY, "Content-Type", "Content-Length", "Host"
    ].map(&:downcase).freeze

    module_function

    # @param base_url [String]
    # @param route [Oblodai::Contract::Route]
    # @param body [String] already-serialized body; "" for GET
    # @param ts [Integer] unix seconds; signed into X-Timestamp
    # @param user_agent [String]
    # @param path_params [Hash, nil]
    # @param query [Hash, nil]
    # @param credentials [Oblodai::RequestBuilder::Credentials, nil]
    # @param idempotency_key [String, nil]
    # @param extra_headers [Hash, nil]
    # @return [Oblodai::RequestBuilder::Built]
    def build(base_url:, route:, body:, ts:, user_agent:, path_params: nil, query: nil,
              credentials: nil, idempotency_key: nil, extra_headers: nil)
      path = join_path(base_url, fill_path(route.path, path_params))
      request_uri = path + query_string(query)

      headers = {}
      (extra_headers || {}).each do |name, value|
        headers[name.to_s] = value.to_s unless RESERVED_HEADERS.include?(name.to_s.downcase)
      end
      headers["Accept"] = "application/json"
      headers["User-Agent"] = user_agent
      has_body = route.method != "GET"
      headers["Content-Type"] = "application/json" if has_body
      headers[Signing::HEADER_IDEMPOTENCY_KEY] = idempotency_key if idempotency_key

      unless route.unsigned?
        unless credentials
          kind = route.auth == :any ? "merchant" : route.auth
          raise ConfigError.new(
            "sdk.missing_credentials",
            "#{route.method} #{route.path} needs a #{kind} API key: pass public_id:/secret: to " \
            "Oblodai::Client.new or set OBLODAI_PUBLIC_ID / OBLODAI_SECRET"
          )
        end
        headers[Signing::HEADER_PUBLIC_ID] = credentials.public_id
        headers[Signing::HEADER_TIMESTAMP] = ts.to_s
        headers[Signing::HEADER_SIGNATURE] = Signing.sign_request(
          credentials.secret, ts: ts, method: route.method, request_uri: request_uri,
                              body: has_body ? body : "", idempotency_key: idempotency_key
        )
      end

      Built.new(url: origin(base_url) + request_uri, method: route.method, headers: headers,
                body: has_body ? body : nil, request_uri: request_uri)
    end

    # Append a route path to the base URL, keeping any path prefix the base carries
    # ("https://host/api" + "/v1/payment" => "/api/v1/payment").
    # @return [String] the path only
    def join_path(base_url, route_path)
      prefix = URI.parse(base_url).path.to_s.sub(%r{/+\z}, "")
      prefix + route_path
    end

    # @return [String] scheme://host[:port] of the base URL
    def origin(base_url)
      uri = URI.parse(base_url)
      port = uri.port && uri.port != uri.default_port ? ":#{uri.port}" : ""
      "#{uri.scheme}://#{uri.host}#{port}"
    end

    # Substitute `{name}` segments; every placeholder must be supplied, values are percent-encoded.
    # @raise [Oblodai::ConfigError] when a value is empty, ".", ".." or contains a slash
    # @return [String]
    def fill_path(template, params = nil)
      params ||= {}
      template.gsub(/\{([a-zA-Z_]+)\}/) do
        name = Regexp.last_match(1)
        raw = params[name.to_sym] || params[name]
        value = raw.nil? ? "" : raw.to_s
        if value.empty? || value == "." || value == ".." || value.include?("/")
          raise ConfigError.new(
            "sdk.bad_path_param",
            "path parameter \"#{name}\" for #{template} must be a non-empty single segment " \
            "(got #{value.inspect})",
            name
          )
        end
        URI.encode_www_form_component(value).gsub("+", "%20")
      end
    end

    # @param query [Hash, nil] nil and empty values are skipped
    # @return [String] "" or "?a=1&b=2"
    def query_string(query)
      pairs = (query || {}).compact.map do |key, value|
        "#{URI.encode_www_form_component(key.to_s)}=#{URI.encode_www_form_component(value.to_s)}"
      end
      pairs.empty? ? "" : "?#{pairs.join("&")}"
    end

    # Serialize a request body once; nil values vanish, a missing POST body becomes `{}`.
    # @return [String]
    def serialize_body(body, method)
      return "" if method == "GET"
      return "{}" if body.nil?

      JSON.generate(deep_compact(body))
    end

    # Drop nil members so an unset keyword never reaches the wire as an explicit null.
    def deep_compact(value)
      case value
      when Hash
        value.each_with_object({}) do |(k, v), out|
          out[k] = deep_compact(v) unless v.nil?
        end
      when Array then value.map { |v| deep_compact(v) }
      else value
      end
    end
  end
end
