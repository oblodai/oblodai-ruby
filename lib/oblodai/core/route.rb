# frozen_string_literal: true

module Oblodai
  # One route of the API, as the runtime needs to know it. The generated route table
  # (`Oblodai::Generated::ROUTES`, keyed by `operationId`) is made of these.
  #
  # @!attribute [r] operation_id
  #   @return [String] the OpenAPI `operationId`
  # @!attribute [r] method
  #   @return [String] "GET" or "POST"
  # @!attribute [r] path
  #   @return [String] path template; `{name}` segments are filled from path parameters
  # @!attribute [r] auth
  #   @return [Symbol] which credential the gate expects: `:public` (none), `:key` (the merchant's
  #     API key signs it) or `:onboard` (the gateway operator's admin token)
  # @!attribute [r] idempotent
  #   @return [Boolean] wrapped in the core's `withIdempotency`: a key is generated when not supplied
  # @!attribute [r] safe
  #   @return [Boolean] read-only: repeating it cannot duplicate a side effect
  # @!attribute [r] bare
  #   @return [Boolean] outside the JSON envelope (binary documents)
  # @!attribute [r] list_kind
  #   @return [Symbol, nil] `:paged` for `{items, paginate}` lists, nil otherwise
  RouteSpec = Struct.new(:operation_id, :method, :path, :auth, :idempotent, :safe, :bare, :list_kind,
                         keyword_init: true) do
    def initialize(*)
      super
      freeze
    end

    # @return [String] "METHOD /path"
    def key
      "#{method} #{path}"
    end

    # @return [Boolean] true when the result is `{items, paginate}`
    def paged?
      list_kind == :paged
    end

    # @return [Boolean] true when the route carries no HMAC signature
    def unsigned?
      %i[public onboard].include?(auth)
    end

    def to_s
      key
    end
  end
end
