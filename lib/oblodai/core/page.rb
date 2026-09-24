# frozen_string_literal: true

module Oblodai
  # Offset pagination over the core's `{items, paginate}` lists.
  #
  # A list method returns a lazy {Page}: it is {Enumerable} over EVERY item of every page,
  # {#each_page} (alias {#by_page}) walks the pages themselves, and {#first_page} gives the single
  # first page with its counters. Nothing is requested until one of those is used, and the first
  # page is fetched once however many ways it is consumed.
  #
  #     client.payments.list_history(limit: 50).each { |payment| puts payment.uuid }  # every item
  #     client.payments.list_history(limit: 50).each_page { |page| puts page.size }    # every page
  #     page = client.payments.list_history(limit: 50).first_page                     # one request
  #     page.has_pages?            # => true
  class Page
    include Enumerable

    DEFAULT_LIMIT = 50

    # @param limit [Integer, nil] page size asked of the core
    # @param offset [Integer, nil] where to start
    # @param first [Oblodai::PageResult, nil] the first page, when it is already at hand
    # @param fetcher [Proc] `->(limit:, offset:) { Oblodai::PageResult }`
    def initialize(limit: nil, offset: nil, first: nil, &fetcher)
      raise ArgumentError, "a Page needs a fetcher block" if fetcher.nil?

      @fetcher = fetcher
      @limit = limit || DEFAULT_LIMIT
      @offset = offset || 0
      @first_page = first
    end

    # The first page and its counters; memoized, so consuming the Page afterwards costs nothing extra.
    # @return [Oblodai::PageResult]
    def first_page
      @first_page ||= @fetcher.call(limit: @limit, offset: @offset)
    end

    # @return [Array] the items of the first page
    def items
      first_page.items
    end

    # @return [Hash{String => Object}] the pagination block of the first page
    def paginate
      first_page.paginate
    end

    # Every page in turn, one request each; the first page is reused when already fetched.
    # Iteration stops on the core's own `paginate.has_pages` flag or on an empty page.
    #
    # @yieldparam page [Oblodai::PageResult]
    # @return [Enumerator, self]
    def each_page
      return enum_for(:each_page) unless block_given?

      offset = @offset
      page = first_page
      loop do
        yield page
        got = page.size
        offset += got
        break if got.zero? || !page.has_pages?

        page = @fetcher.call(limit: @limit, offset: offset)
      end
      self
    end
    alias by_page each_page

    # Walk every item of every page, one request per page.
    # @yieldparam item [Object]
    # @return [Enumerator, self]
    def each(&block)
      return enum_for(:each) unless block_given?

      each_page { |page| page.items.each(&block) }
      self
    end

    # Collect every item into an array, at most `max_items` of them. A cap never costs an extra
    # page request.
    # @param max_items [Integer, nil]
    # @return [Array]
    def all(max_items = nil)
      return to_a if max_items.nil?
      return [] unless max_items.positive?

      out = []
      each do |item|
        out << item
        break if out.size >= max_items
      end
      out
    end

    def inspect
      "#<Oblodai::Page limit=#{@limit} offset=#{@offset} fetched=#{!@first_page.nil?}>"
    end
  end

  # One page of a list: the items plus the core's pagination block.
  class PageResult
    include Enumerable

    # @return [Array] the items of this page, decoded into models
    attr_reader :items
    # @return [Hash{String => Object}] `total`, `per_page`, `offset`, `has_pages`, as the core sent them
    attr_reader :paginate

    def initialize(items:, paginate:)
      @items = items.freeze
      @paginate = (paginate || {}).freeze
      freeze
    end

    # @return [Integer]
    def total
      @paginate.fetch("total", 0).to_i
    end

    # @return [Integer]
    def per_page
      @paginate.fetch("per_page", @items.size).to_i
    end

    # @return [Integer]
    def offset
      @paginate.fetch("offset", 0).to_i
    end

    # @return [Boolean] the core's own "there is more" flag
    def has_pages?
      @paginate["has_pages"] == true
    end

    # Iterate THIS page's items only (the {Page} walks every page).
    def each(&)
      @items.each(&)
    end

    def size
      @items.size
    end

    def empty?
      @items.empty?
    end

    def to_h
      { items: @items.map { |i| i.respond_to?(:to_h) ? i.to_h : i }, paginate: @paginate }
    end

    def inspect
      "#<Oblodai::PageResult items=#{@items.size} total=#{total} has_pages=#{has_pages?}>"
    end
  end
end
