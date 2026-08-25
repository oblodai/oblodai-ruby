# frozen_string_literal: true

require "json"
require "time"
require_relative "../errors"

module Oblodai
  # Response envelopes, as `httpx`/`apiutil` on the core write them:
  #
  #     success : { "state": 0, "result": <payload> }
  #     list    : result = { "items": [...], "paginate": { total, per_page, offset, has_pages } }
  #     error   : { "error": { code, message, field?, retryable, retry_after?, request_id? } }
  #
  # Every non-`bare` route uses these; bare routes (PDF documents, health pages) bypass this module.
  module Envelope
    # Outcome of {Envelope.decode}: either a result or an error, never both.
    Decoded = Struct.new(:ok, :result, :error, keyword_init: true) do
      def ok?
        ok
      end
    end

    module_function

    # Interpret a response body. `text` is the raw body so non-JSON failures keep their evidence.
    #
    # @param http_status [Integer]
    # @param text [String]
    # @param retry_after [String, nil] the `Retry-After` header value, if any
    # @param location [String, nil] the `Location` header value, for redirects
    # @return [Oblodai::Envelope::Decoded]
    # @raise [Oblodai::ContractError] on a 2xx body that is not an envelope
    def decode(http_status, text, retry_after: nil, location: nil)
      retry_after_header = parse_retry_after(retry_after)

      if http_status >= 300 && http_status < 400
        where = location ? " to #{location}" : ""
        return failure(Oblodai.api_error_from(
                         http_status,
                         { "code" => "internal",
                           "message" => "unexpected redirect (HTTP #{http_status})#{where}; check base_url" },
                         raw: text, synthetic: true
                       ))
      end

      begin
        body = text.to_s.empty? ? nil : JSON.parse(text)
      rescue JSON::ParserError
        return failure(no_envelope_error(http_status, text, retry_after_header)) if http_status >= 400

        raise ContractError.new("expected a JSON envelope, got #{describe(text)}", http_status, text)
      end

      if body.is_a?(Hash) && body["error"].is_a?(Hash)
        return failure(Oblodai.api_error_from(http_status, body["error"], raw: body,
                                                                          retry_after_header: retry_after_header))
      end
      return failure(no_envelope_error(http_status, text, retry_after_header)) if http_status >= 400
      if body.is_a?(Hash) && body["state"].zero? && body.key?("result")
        return Decoded.new(ok: true,
                           result: body["result"])
      end

      raise ContractError.new(
        "response is not a {state:0,result} envelope: #{describe(text)}", http_status, body
      )
    end

    # `Retry-After` as delta-seconds or an HTTP-date.
    # @return [Integer, nil] nil when absent or unparsable
    def parse_retry_after(value, now = Time.now)
      return nil if value.nil?

      v = value.to_s.strip
      return nil if v.empty?
      return v.to_i if /\A\d+\z/.match?(v)

      begin
        [0, (Time.httpdate(v) - now).ceil].max
      rescue ArgumentError
        nil
      end
    end

    # Assert the paged-list shape on a decoded result.
    # @raise [Oblodai::ContractError]
    # @return [Hash]
    def as_page(result, http_status = 200)
      return result if result.is_a?(Hash) && result["items"].is_a?(Array) && result["paginate"].is_a?(Hash)

      raise ContractError.new("expected {items, paginate} list result", http_status, result)
    end

    # Assert the plain-list shape (`{items}` without paginate).
    # @raise [Oblodai::ContractError]
    # @return [Hash]
    def as_plain_list(result, http_status = 200)
      return result if result.is_a?(Hash) && result["items"].is_a?(Array)

      raise ContractError.new("expected {items} list result", http_status, result)
    end

    def failure(error)
      Decoded.new(ok: false, error: error)
    end

    def no_envelope_error(http_status, text, retry_after_header)
      Oblodai.api_error_from(
        http_status,
        { "code" => "internal",
          "message" => "HTTP #{http_status} without an Oblodai error envelope (#{describe(text)}) — " \
                       "the answer came from a proxy or load balancer, not the API" },
        raw: text, synthetic: true, retry_after_header: retry_after_header
      )
    end

    def describe(text)
      s = text.to_s
      head = s[0, 120].to_s.gsub(/\s+/, " ")
      return "<empty body>" if head.empty?

      s.length > 120 ? "#{head}…" : head
    end
  end
end
