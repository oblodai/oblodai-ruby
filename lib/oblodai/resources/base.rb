# frozen_string_literal: true

require_relative "../core/page"
require_relative "../core/envelope"
require_relative "../contract/routes"
require_relative "../models/common"

module Oblodai
  # A binary response (PDF/CSV documents).
  class FileResult
    # @return [String] the bytes, ASCII-8BIT encoded
    attr_reader :bytes
    # @return [String] MIME type the core sent
    attr_reader :content_type
    # @return [String, nil] name suggested by `Content-Disposition`
    attr_reader :filename

    def initialize(bytes:, content_type:, filename: nil)
      @bytes = bytes
      @content_type = content_type
      @filename = filename
      freeze
    end

    # @return [Integer]
    def size
      @bytes.bytesize
    end

    # Write the document to disk.
    # @param path [String] defaults to {#filename} in the working directory
    # @return [String] the path written
    def save(path = nil)
      target = path || @filename or raise ArgumentError, "no path given and the response carried no filename"
      File.binwrite(target, @bytes)
      target
    end

    def inspect
      "#<Oblodai::FileResult #{@content_type} #{size} bytes filename=#{@filename.inspect}>"
    end
  end

  module Resources
    # Base class of every resource namespace. It turns a route key plus keyword arguments into a
    # transport call and decodes the result into a model.
    class Base
      # Per-call options every resource method accepts alongside the request body:
      #
      # - `idempotency_key:` your own key; generated automatically on create routes when omitted and
      #   REFUSED on routes the core does not deduplicate (`sdk.idempotency_unsupported`).
      # - `timeout_ms:` per-attempt timeout.
      # - `deadline_ms:` overall budget for the call including retries.
      # - `prefer_payout_key:` sign with the payout key on a route that accepts either kind.
      OPTION_KEYS = %i[idempotency_key timeout_ms deadline_ms prefer_payout_key].freeze

      # Remove the per-call options from a keyword hash, leaving the request body behind.
      # @param params [Hash]
      # @return [Hash]
      def self.take_options!(params)
        OPTION_KEYS.each_with_object({}) do |key, out|
          out[key] = params.delete(key) if params.key?(key)
        end
      end

      # @param transport [Oblodai::Transport]
      def initialize(transport)
        @transport = transport
      end

      private

      def route(key)
        Contract::ROUTES.fetch(key)
      end

      # Call an envelope route and decode `result` into `model` (or return it raw when nil).
      def call(key, body = nil, model: nil, path_params: nil, query: nil, **options)
        result = @transport.call(route(key), body: normalize(body), query: query,
                                             path_params: path_params, **options)
        decode(result, model)
      end

      # Call a paged list route and return a lazy {Oblodai::Page}.
      def page(key, model:, params: {}, path_params: nil, via_query: false, **options)
        params = normalize(params) || {}
        limit = params.delete(:limit) || params.delete("limit")
        offset = params.delete(:offset) || params.delete("offset")
        # One key per page would be wrong on both sides: the core would replay page 1 forever.
        options.delete(:idempotency_key)
        spec = route(key)
        use_query = spec.method == "GET" || via_query

        Page.new(limit: limit, offset: offset) do |limit:, offset:|
          page_params = params.merge(limit: limit, offset: offset)
          result = @transport.call(
            spec,
            body: use_query ? nil : page_params,
            query: use_query ? page_params : nil,
            path_params: path_params, **options
          )
          checked = Envelope.as_page(result)
          PageResult.new(items: decode_list(checked["items"], model),
                         paginate: Models::Paginate.from(checked["paginate"]))
        end
      end

      # Call a plain list route (`{items}` without paginate) and return the decoded items.
      def plain_list(key, body = nil, model:, **options)
        result = @transport.call(route(key), body: normalize(body), **options)
        decode_list(Envelope.as_plain_list(result)["items"], model)
      end

      # Call a bare (binary) route.
      def file(key, body: nil, query: nil, path_params: nil, **options)
        raw = @transport.call_raw(route(key), body: normalize(body), query: query,
                                              path_params: path_params, **options)
        FileResult.new(bytes: raw.body, content_type: raw.content_type || "application/octet-stream",
                       filename: filename_from(raw.header("content-disposition")))
      end

      def decode(result, model)
        return result if model.nil?

        model.from(result)
      end

      def decode_list(items, model)
        return Array(items) if model.nil?

        model.from_list(items)
      end

      # Drop nil keyword arguments so an unset option never reaches the wire as an explicit null.
      def normalize(body)
        return nil if body.nil?
        return body unless body.is_a?(Hash)

        cleaned = body.compact
        cleaned.empty? ? {} : cleaned
      end

      def filename_from(disposition)
        return nil if disposition.nil?

        if (utf8 = /filename\*=UTF-8''([^;]+)/i.match(disposition))
          return URI.decode_www_form_component(utf8[1])
        end

        /filename="?([^";]+)"?/i.match(disposition)&.captures&.first
      end
    end
  end
end
