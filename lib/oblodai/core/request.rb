# frozen_string_literal: true

require "bigdecimal"
require "json"
require "uri"
require_relative "signing"
require_relative "../errors"
require_relative "../helpers/money"

module Oblodai
  # Builds the outgoing request — URL, headers, body — as a pure function of its inputs, so the
  # signing material (what is signed) and the wire bytes (what is sent) come from one place and
  # cannot disagree. Nothing here touches the network or the clock.
  module RequestBuilder
    # Credentials of one key pair. Frozen, and its secret never prints: `inspect`, `to_s` and
    # `to_json` show a placeholder, so a `p credentials` or a structured log of anything holding one
    # cannot put the signing key in a log file. Read it as `credentials.secret` when you mean to.
    Credentials = Struct.new(:public_id, :secret, keyword_init: true) do
      def initialize(*)
        super
        freeze
      end

      def inspect
        "#<Oblodai::RequestBuilder::Credentials public_id=#{public_id.inspect} secret=[redacted]>"
      end
      alias_method :to_s, :inspect

      def to_h
        { public_id: public_id, secret: "[redacted]" }
      end

      def to_json(*args)
        require "json"
        to_h.to_json(*args)
      end
    end

    # A request ready to hand to an HTTP adapter.
    #
    # @!attribute [r] request_uri
    #   @return [String] what was signed (path + query); kept for debugging signature mismatches
    Built = Struct.new(:url, :method, :headers, :body, :request_uri, keyword_init: true) do
      def initialize(*)
        super
        freeze
      end
    end

    # Sent on `onboard` routes only; the transport decides when to supply it.
    HEADER_ADMIN_TOKEN = "X-Admin-Token"
    # The call's own id, the same on every attempt: `request_id:`, else a caller header, else a UUID.
    HEADER_REQUEST_ID = "X-Request-ID"

    # Request fields the contract types as a JSON `number` that are not money (a tolerance in
    # percent). A Float anywhere else in a body is an amount losing precision; a spec keeps this set
    # equal to the `number` properties of the contract's request schemas.
    NON_MONEY_NUMBERS = ["accuracy_payment_percent"].freeze

    # Headers the SDK owns. A caller-supplied header with one of these names is dropped, matched
    # case-insensitively: `accept: text/html` next to the SDK's `Accept` would otherwise reach the
    # wire as a second value, and a caller `X-Admin-Token` would travel on signed merchant routes it
    # has no business on.
    RESERVED_HEADERS = [
      Signing::HEADER_PUBLIC_ID, Signing::HEADER_SIGNATURE, Signing::HEADER_TIMESTAMP,
      Signing::HEADER_IDEMPOTENCY_KEY, HEADER_ADMIN_TOKEN, HEADER_REQUEST_ID, "Accept", "User-Agent",
      "Content-Type", "Content-Length", "Host"
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
    # @param request_id [String, nil] sent as `X-Request-ID`
    # @return [Oblodai::RequestBuilder::Built]
    def build(base_url:, route:, body:, ts:, user_agent:, path_params: nil, query: nil,
              credentials: nil, idempotency_key: nil, extra_headers: nil, admin_token: nil,
              request_id: nil)
      path = join_path(base_url, fill_path(route.path, path_params))
      request_uri = path + query_string(query)

      headers = {}
      (extra_headers || {}).each do |name, value|
        next if RESERVED_HEADERS.include?(name.to_s.downcase)

        assert_header_value!(name.to_s, value)
        headers[name.to_s] = value.to_s
      end
      headers["Accept"] = "application/json"
      headers["User-Agent"] = user_agent
      has_body = route.method != "GET"
      headers["Content-Type"] = "application/json" if has_body
      headers[Signing::HEADER_IDEMPOTENCY_KEY] = idempotency_key if idempotency_key
      if request_id
        assert_header_value!(HEADER_REQUEST_ID, request_id)
        headers[HEADER_REQUEST_ID] = request_id
      end
      if admin_token
        assert_header_value!(HEADER_ADMIN_TOKEN, admin_token)
        headers[HEADER_ADMIN_TOKEN] = admin_token.to_s
      end

      unless route.unsigned?
        unless credentials
          raise ConfigError.new(
            "sdk.missing_credentials",
            "#{route.method} #{route.path} is signed with the merchant's API key: pass " \
            "public_id:/secret: to Oblodai::Client.new or set OBLODAI_PUBLIC_ID / OBLODAI_SECRET"
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

    # Caller header values must be printable ASCII on one line. A CR or LF would let a caller-
    # controlled value append headers of its own (request splitting); a non-ASCII byte is rejected
    # by the HTTP library at best and mangled at worst, so it is refused here, where the error names
    # the header.
    # @raise [Oblodai::ConfigError]
    # @return [void]
    def assert_header_value!(name, value)
      return if value.is_a?(String) && /\A[\x20-\x7e\t]*\z/.match?(value)
      return if (value.is_a?(Integer) || value.is_a?(Symbol)) && /\A[\x20-\x7e\t]*\z/.match?(value.to_s)

      raise ConfigError.new(
        "sdk.bad_header",
        "header \"#{name}\" must be printable ASCII on a single line " \
        "(no CR/LF, no non-ASCII characters)",
        name
      )
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
        # The unreserved set of RFC 3986 / encodeURIComponent, so a path parameter is escaped the
        # same way in every Oblodai SDK — form encoding would turn a space into "+" and escape
        # characters the gateway sees unescaped from the others.
        URI::DEFAULT_PARSER.escape(value, /[^A-Za-z0-9\-_.!~*'()]/)
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

    # Serialize a request body once; a missing POST body becomes `{}`, GET signs nothing. Models
    # become their wire Hash, `BigDecimal` its decimal string; a `Float` amount is refused before
    # anything is signed (`sdk.float_amount`), and so is any value JSON cannot carry (`sdk.bad_body`).
    # A nil member is sent as JSON null: the generated methods leave out every keyword the caller
    # did not pass, so a nil that reaches this point is one the caller meant.
    # @return [String]
    # @raise [Oblodai::ConfigError]
    def serialize_body(body, method)
      return "" if method == "GET"
      return "{}" if body.nil?

      JSON.generate(wire(body, ""))
    end

    # The JSON-ready form of a request value; `path` names the field in error messages.
    # @raise [Oblodai::ConfigError]
    def wire(value, path)
      case value
      when nil, true, false, String, Integer then value
      when Float then wire_float(value, path)
      when BigDecimal then wire_decimal(value, path)
      when Symbol then value.to_s
      when Hash then wire_hash(value, path)
      when Array then value.each_with_index.map { |item, i| wire(item, "#{path}[#{i}]") }
      else
        return wire(value.to_h, path) if model?(value)

        bad_body!("#{describe(path)} is a #{value.class}, which is not JSON; amounts are decimal strings " \
                  "or BigDecimal, times are RFC 3339 strings")
      end
    end

    def wire_hash(value, path)
      value.to_h do |key, item|
        name = key.to_s
        [name, wire(item, path.empty? ? name : "#{path}.#{name}")]
      end
    end

    # A Float is money losing precision — except in the few `number` fields that are not money.
    def wire_float(value, path)
      unless NON_MONEY_NUMBERS.include?(path.split(".").last.to_s.sub(/\[\d+\]\z/, ""))
        Money.float_amount!(value, path.empty? ? "body" : path)
      end
      bad_body!("#{describe(path)} is not a finite number (#{value})") unless value.finite?
      value
    end

    def wire_decimal(value, path)
      bad_body!("#{describe(path)} is a non-finite BigDecimal (#{value})") unless value.finite?

      Money.decimal_string(value)
    end

    def model?(value)
      defined?(Oblodai::Models::Base) && value.is_a?(Oblodai::Models::Base)
    end

    def describe(path)
      path.empty? ? "the request body" : "field #{path}"
    end

    def bad_body!(message)
      raise ConfigError.new("sdk.bad_body", message, "body")
    end
  end
end
