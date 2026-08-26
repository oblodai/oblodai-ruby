# frozen_string_literal: true

module Oblodai
  module Contract
    # One route of the core's conformance table. The registry in `routes.rb` is generated from
    # contract/contract.json, so every route the SDK can call is one the core declares, with the
    # same auth gate, the same idempotency wrapper and the same envelope shape.
    #
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
    # @!attribute [r] list
    #   @return [Symbol, nil] :paged for `{items, paginate}`, :plain for `{items}`, nil otherwise
    Route = Struct.new(:method, :path, :auth, :idempotent, :safe, :bare, :list, keyword_init: true) do
      # @return [String] the registry key, "METHOD /path"
      def key
        "#{method} #{path}"
      end

      # @return [Boolean] true when the result is `{items, paginate}`
      def paged?
        list == :paged
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
end
