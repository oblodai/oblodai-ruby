# frozen_string_literal: true

require_relative "../core/page"
require_relative "../core/envelope"
require_relative "../contract/routes"
require_relative "../models/common"
require_relative "../errors"

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
    #
    # With no argument the file is written to the working directory under the name the SERVER
    # suggested, reduced to a bare basename first: a `Content-Disposition` of
    # `filename="../../etc/cron.d/x"` names a path outside the directory the caller meant, and the
    # name is chosen by whatever answered the request. Pass an explicit `path` when you want one.
    #
    # @param path [String, nil] where to write; defaults to {#safe_filename} in the working directory
    # @raise [ArgumentError] when no path is given and the suggested name is unusable
    # @return [String] the path written
    def save(path = nil)
      target = path || safe_filename
      if target.nil?
        raise ArgumentError,
              "no path given and the response carried no usable filename " \
              "(Content-Disposition: #{@filename.inspect}) — pass one to #save"
      end

      File.binwrite(target, @bytes)
      target
    end

    # The server-suggested name reduced to a single path segment, or nil when nothing usable is
    # left of it. {#filename} keeps the raw value for logging.
    # @return [String, nil]
    def safe_filename
      return nil if @filename.nil?

      name = File.basename(@filename.to_s.tr("\\", "/").delete("\0"))
      return nil if name.empty? || name.include?("/") || [".", ".."].include?(name)

      name
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
      OPTION_KEYS = %i[idempotency_key timeout_ms deadline_ms].freeze

      # Remove the per-call options from a keyword hash, leaving the request body behind.
      # @param params [Hash]
      # @return [Hash]
      def self.take_options!(params)
        OPTION_KEYS.each_with_object({}) do |key, out|
          out[key] = params.delete(key) if params.key?(key)
        end
      end

      # Methods that take no request body collect their keywords as per-call options; a misspelled
      # one would otherwise reach the transport as an unknown keyword and surface as a bare
      # ArgumentError from inside the SDK instead of an Oblodai error naming the mistake.
      # @raise [Oblodai::ConfigError]
      # @return [void]
      def self.assert_options!(options, route_key)
        unknown = options.keys - OPTION_KEYS
        return if unknown.empty?

        raise ConfigError.new(
          "sdk.bad_config",
          "#{route_key}: unknown option(s) #{unknown.map(&:inspect).join(", ")}; " \
          "this method accepts #{OPTION_KEYS.map(&:inspect).join(", ")}",
          unknown.first.to_s
        )
      end

      # @param transport [Oblodai::Transport]
      def initialize(transport)
        @transport = transport
      end

      private

      def route(key)
        Contract::ROUTES.fetch(key)
      end

      # Accept either the object's id as a string or the model that carries it, so a value the SDK
      # just returned can be passed straight back.
      # @param ref [String, Oblodai::Models::Model, Hash]
      # @param field [Symbol] the id field on the model
      # @return [String]
      def id_of(ref, field)
        return ref if ref.is_a?(String) || ref.nil?
        return ref[field].to_s if ref.respond_to?(:[]) && !ref[field].nil?

        ref.to_s
      end

      # Call an envelope route and decode `result` into `model` (or return it raw when nil).
      def call(key, body = nil, model: nil, path_params: nil, query: nil, **options)
        Base.assert_options!(options, key)
        result = @transport.call(route(key), body: body, query: query,
                                             path_params: path_params, **options)
        decode(result, model)
      end

      # Call a paged list route and return a lazy {Oblodai::Page}. Nil keywords are dropped in one
      # place only — {Oblodai::RequestBuilder.serialize_body} for bodies, `query_string` for
      # queries — so "unset" never reaches the wire as an explicit null.
      def page(key, model:, params: {}, path_params: nil, via_query: false, **options)
        Base.assert_options!(options, key)
        params ||= {}
        limit = params.delete(:limit) || params.delete("limit")
        offset = params.delete(:offset) || params.delete("offset")
        spec = route(key)
        # One key across a paging loop would make the core replay page 1 forever, and a key per page
        # is not what the caller asked for either — so this is refused loudly, with the same code the
        # transport raises on any other route the core does not deduplicate. Dropping it silently
        # would leave the caller believing a re-send is deduplicated when it is not.
        if options.key?(:idempotency_key)
          raise ConfigError.new(
            "sdk.idempotency_unsupported",
            "#{spec.key} is a list route and does not deduplicate by Idempotency-Key; " \
            "remove idempotency_key from this call",
            "idempotency_key"
          )
        end
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
        Base.assert_options!(options, key)
        result = @transport.call(route(key), body: body, **options)
        decode_list(Envelope.as_plain_list(result)["items"], model)
      end

      # Call a bare (binary) route.
      def file(key, body: nil, query: nil, path_params: nil, **options)
        Base.assert_options!(options, key)
        raw = @transport.call_raw(route(key), body: body, query: query,
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
