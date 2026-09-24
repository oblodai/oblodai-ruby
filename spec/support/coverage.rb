# frozen_string_literal: true

# The coverage ledger: which client method calls which operation, worked out from the code. Every
# namespace method is called once on a probe whose `_request` records the route instead of sending
# it, so the ledger cannot drift from the generated resources. Path parameters get a placeholder;
# everything else is left to its default.
module Coverage
  # The value every path parameter gets in a probe or a wiring test.
  PATH_VALUE = "x1"

  # Raised by the probe's `_request` with the route the method asked for.
  class Probe < StandardError
    attr_reader :route

    def initialize(route)
      super(route.operation_id)
      @route = route
    end
  end

  module_function

  # @return [Hash{Symbol => Oblodai::Resources::Base}] every generated namespace of a client
  def namespaces(client)
    Oblodai::Client::RESOURCES.keys.to_h { |name| [name, client.public_send(name)] }
  end

  # @return [Integer] how many path parameters (required positionals) a method takes
  def positional(method)
    method.parameters.count { |kind, _| kind == :req }
  end

  # @return [Hash{String => Array(Symbol, Symbol)}] operationId => [namespace, method]
  def ledger
    @ledger ||= begin
      out = {}
      client = Oblodai::Client.new(public_id: "p", secret: "s", env: {})
      namespaces(client).each do |namespace, resource|
        resource.define_singleton_method(:_request) { |route, *, **| raise Probe, route }
        resource.class.public_instance_methods(false).each do |name|
          method = resource.method(name)
          method.call(*[PATH_VALUE] * positional(method))
        rescue Probe => e
          op = e.route.operation_id
          raise "#{op}: reached by #{out[op].inspect} and #{[namespace, name].inspect}" if out.key?(op)

          out[op] = [namespace, name]
        end
      end
      out
    end
  end

  # Call the method behind `operation_id` with placeholder path parameters.
  def call(client, operation_id, *, **)
    namespace, name = ledger.fetch(operation_id)
    method = client.public_send(namespace).method(name)
    method.call(*[PATH_VALUE] * positional(method), *, **)
  end
end
