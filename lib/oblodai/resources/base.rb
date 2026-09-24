# frozen_string_literal: true

require "uri"
require_relative "../core/options"
require_relative "../core/page"
require_relative "../core/poller"
require_relative "../core/raw"
require_relative "../core/route"
require_relative "../core/transport"
require_relative "../errors"
require_relative "../lro"
require_relative "../models/base"

module Oblodai
  # A binary response (PDF/CSV documents).
  class FileResult
    # @return [String] the bytes, ASCII-8BIT encoded
    attr_reader :bytes
    # @return [String] MIME type the core sent
    attr_reader :content_type
    # @return [String, nil] name suggested by `Content-Disposition`
    attr_reader :filename

    # The bytes of a `bare` route's answer, with their type and file name.
    # @param response [Oblodai::HTTP::Response]
    # @return [Oblodai::FileResult]
    def self.from_response(response)
      new(bytes: response.body.to_s.b, content_type: response.content_type || "application/octet-stream",
          filename: filename_from(response.header("content-disposition")))
    end

    # Pull the file name out of a `Content-Disposition` header.
    # @return [String, nil]
    def self.filename_from(disposition)
      return nil if disposition.nil?

      if (utf8 = /filename\*=UTF-8''([^;]+)/i.match(disposition))
        return URI.decode_www_form_component(utf8[1])
      end

      /filename="?([^";]+)"?/i.match(disposition)&.captures&.first
    end

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
    # Base of every resource namespace on {Oblodai::Client} (the namespaces themselves are
    # generated). Every method takes the call options of {Oblodai::RequestOptions} as trailing
    # keywords: `idempotency_key:`, `timeout:` (seconds, per attempt), `max_retries:`,
    # `extra_headers:` and `request_id:` (sent as `X-Request-ID`).
    class Base
      # @param transport [Oblodai::Transport]
      def initialize(transport)
        @transport = transport
        @raw_response = false
      end

      # The same methods, returning {Oblodai::RawAPIResponse} (status, headers, `request_id`,
      # `parse`) instead of the parsed result.
      # @return [self]
      def with_raw_response
        clone = dup
        clone.instance_variable_set(:@raw_response, true)
        clone
      end

      def inspect
        "#<#{self.class.name}#{" (raw responses)" if @raw_response}>"
      end

      private

      # Call a route the way its kind asks; the one entry point of generated methods.
      #
      # An envelope route returns its `result`, or `parse.call(result)` when given; a long-running
      # operation ({Oblodai::LRO}) returns an {Oblodai::Job} around that value. A paged list returns a
      # lazy {Oblodai::Page} whose items go through `parse`; `limit`/`offset` in the body (the query
      # for GET) pick the first page. A `bare` route returns an {Oblodai::FileResult}. Through
      # {#with_raw_response} each returns an {Oblodai::RawAPIResponse} whose `parse` gives the same
      # value.
      #
      # @param route [Oblodai::RouteSpec]
      # @param body [Hash, nil]
      # @param options [Oblodai::RequestOptions]
      # @param path_params [Hash, nil]
      # @param query [Hash, nil]
      # @param parse [#call, nil]
      def _request(route, body, options, path_params: nil, query: nil, parse: nil)
        unless options.is_a?(RequestOptions)
          raise TypeError, "options must be Oblodai::RequestOptions, not #{options.class}"
        end
        return paged(route, body, options, path_params, query, parse) if route.paged?

        call = Transport::CallOptions.from(options, body: body, query: query, path_params: path_params)
        decode = decoder(route, options, parse)
        answer = @transport.call_raw(route, call)
        @raw_response ? RawAPIResponse.new(route, answer, decode) : decode.call(answer)
      end

      # How a 2xx answer becomes the method's value.
      def decoder(route, options, parse)
        return ->(answer) { FileResult.from_response(answer.response) } if route.bare

        job = job_plan(route)
        lambda do |answer|
          result = Transport.unwrap(route, answer.response)
          value = parse ? parse.call(result) : result
          job ? build_job(job, options, result, value) : value
        end
      end

      def paged(route, body, options, path_params, query, parse)
        plan = Oblodai::PagedRequest.new(route, body, query, options, path_params, parse)
        transport = @transport
        fetch = lambda do |limit:, offset:|
          plan.page(transport.call(route, plan.call_options(limit, offset)))
        end
        return Page.new(limit: plan.limit, offset: plan.offset, &fetch) unless @raw_response

        answer = transport.call_raw(route, plan.call_options(plan.first_limit, plan.first_offset))
        RawAPIResponse.new(route, answer, lambda { |raw|
          first = plan.page(Transport.unwrap(route, raw.response))
          Page.new(limit: plan.limit, offset: plan.offset, first: first, &fetch)
        })
      end

      # The polls of a long-running operation, or nil for an ordinary route.
      def job_plan(route)
        poll_id = LRO::CREATES[route.operation_id.to_s]
        return nil if poll_id.nil?

        poll = LRO::POLLS.fetch(poll_id)
        { poll: generated_route(poll_id), id_field: poll.id_field, model: generated_model(poll.model),
          download: poll.download && generated_route(poll.download) }
      end

      def build_job(plan, options, result, value)
        id = result.is_a?(Hash) ? result[plan[:id_field]] : nil
        if id.nil? || id.to_s.empty?
          raise ContractError.new("long-running call answered without #{plan[:id_field]}", 200, result)
        end

        # The create call's timeout, retries and headers; not its idempotency key (it belongs to the
        # create) and a fresh request id per poll.
        follow = RequestOptions.new(timeout: options.timeout, max_retries: options.max_retries,
                                    extra_headers: options.extra_headers)
        transport = @transport
        poll = lambda do
          answer = transport.call(plan[:poll], Transport::CallOptions.from(follow, body: { plan[:id_field] => id }))
          plan[:model] ? plan[:model].from_h(answer) : answer
        end
        download = plan[:download] && lambda do
          call = Transport::CallOptions.from(follow, query: { plan[:id_field] => id })
          FileResult.from_response(transport.call_raw(plan[:download], call).response)
        end
        Job.new(id: id.to_s, result: value, poll: poll, download: download)
      end

      def generated_route(operation_id)
        routes = defined?(Oblodai::Generated::ROUTES) ? Oblodai::Generated::ROUTES : {}
        routes.fetch(operation_id) do
          raise ConfigError.new("sdk.lro_unresolved",
                                "no route for operation #{operation_id}, needed to follow a long-running call")
        end
      end

      def generated_model(name)
        Oblodai::Models.const_defined?(name, false) ? Oblodai::Models.const_get(name, false) : nil
      end
    end
  end

  # A generated paged-list call, worked out once: the request every page repeats, and where the
  # first page starts.
  class PagedRequest
    # @return [Integer, nil]
    attr_reader :limit, :offset

    def initialize(route, body, query, options, path_params, parse)
      @route = route
      @body = page_params(body, "body")
      @query = query.nil? ? nil : page_params(query, "query")
      @limit = @body.delete("limit")
      @offset = @body.delete("offset")
      unless @query.nil?
        @limit = @query.delete("limit") || @limit
        @offset = @query.delete("offset") || @offset
      end
      if options.idempotency_key && !route.idempotent
        # One key reused across pages would replay page 1 forever.
        raise ConfigError.new(
          "sdk.idempotency_unsupported",
          "#{route.key} does not deduplicate by Idempotency-Key; remove idempotency_key from this call",
          "idempotency_key"
        )
      end
      @options = RequestOptions.new(**options.to_h, idempotency_key: nil)
      @path_params = path_params
      @parse = parse
    end

    # The first page's size and offset, with the defaults {Oblodai::Page} applies.
    def first_limit
      @limit || Page::DEFAULT_LIMIT
    end

    def first_offset
      @offset || 0
    end

    # @return [Oblodai::Transport::CallOptions]
    def call_options(limit, offset)
      paging = { "limit" => limit, "offset" => offset }
      if @route.method == "GET"
        body = @body.empty? ? nil : @body
        query = (@query || {}).merge(paging)
      else
        body = @body.merge(paging)
        query = @query
      end
      Transport::CallOptions.from(@options, body: body, query: query, path_params: @path_params)
    end

    # @return [Oblodai::PageResult]
    def page(result)
      checked = Envelope.as_page(result)
      items = checked["items"]
      PageResult.new(items: @parse ? items.map { |item| @parse.call(item) } : items,
                     paginate: checked["paginate"])
    end

    private

    def page_params(value, what)
      case value
      when nil then {}
      when Hash then value.to_h { |key, item| [key.to_s, item] }
      else raise TypeError, "a list call's #{what} must be a Hash, not #{value.class}"
      end
    end
  end
end
