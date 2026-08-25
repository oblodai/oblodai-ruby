# frozen_string_literal: true

module Oblodai
  # Offset pagination over the core's `{items, paginate}` lists.
  #
  # A list method returns a {Page}: it is {Enumerable} over EVERY item of every page, and
  # {#first_page} gives the single first page with its counters. Nothing is requested until one of
  # those is used, and the first page is fetched once however many ways it is consumed.
  #
  #     client.payments.history(limit: 50).each { |payment| puts payment.uuid }  # walks all pages
  #     page = client.payments.history(limit: 50).first_page                     # one request
  #     page.items.size            # => 50
  #     page.paginate.has_pages    # => true
  class Page
    include Enumerable

    DEFAULT_LIMIT = 50

    # @param limit [Integer, nil] page size asked of the core
    # @param offset [Integer, nil] where to start
    # @param fetcher [Proc] `->(limit:, offset:) { Oblodai::PageResult }`
    def initialize(limit: nil, offset: nil, &fetcher)
      @fetcher = fetcher
      @limit = limit || DEFAULT_LIMIT
      @offset = offset || 0
      @first_page = nil
    end

    # The first page and its counters; memoized, so consuming the Page afterwards costs nothing extra.
    # @return [Oblodai::PageResult]
    def first_page
      @first_page ||= @fetcher.call(limit: @limit, offset: @offset)
    end

    # Walk every item of every page, one request at a time. Iteration stops on the core's own
    # `paginate.has_pages` flag or on a short page, whichever comes first.
    #
    # @yieldparam item [Object]
    # @return [Enumerator, self]
    def each(&block)
      return enum_for(:each) unless block_given?

      offset = @offset
      pending = first_page
      loop do
        page = pending || @fetcher.call(limit: @limit, offset: offset)
        pending = nil
        page.items.each(&block)
        got = page.items.size
        offset += got
        break if got.zero? || !page.paginate.has_pages
      end
      self
    end

    # Collect every item into an array, at most `max_items` of them.
    # @param max_items [Integer, nil]
    # @return [Array]
    def all(max_items = nil)
      return to_a if max_items.nil?

      out = []
      each do |item|
        break if out.size >= max_items

        out << item
      end
      out
    end

    def inspect
      "#<Oblodai::Page limit=#{@limit} offset=#{@offset} fetched=#{!@first_page.nil?}>"
    end
  end

  # One page of a list: the items plus the core's counters.
  class PageResult
    include Enumerable

    # @return [Array] the items of this page, decoded into models
    attr_reader :items
    # @return [Oblodai::Models::Paginate]
    attr_reader :paginate

    def initialize(items:, paginate:)
      @items = items.freeze
      @paginate = paginate
      freeze
    end

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
      { items: @items.map { |i| i.respond_to?(:to_h) ? i.to_h : i }, paginate: @paginate.to_h }
    end

    def inspect
      "#<Oblodai::PageResult items=#{@items.size} paginate=#{@paginate.to_h}>"
    end
  end
end
