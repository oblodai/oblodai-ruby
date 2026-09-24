# frozen_string_literal: true

# A scripted gateway for the README and example specs: whatever route a snippet calls, it answers
# with a minimal valid body for the model the generated method parses (spec/support/samples.rb), a
# PDF for a document route. A few answers are shaped so a script walks its main path.
class Gateway
  # operationId => fields merged into the generic answer
  SHAPES = {
    "getPaymentInfo" => { "status" => "paid" },
    "validatePayout" => { "valid" => true },
    "getBatchInfo" => { "status" => "completed" },
    "getDocumentJob" => { "status" => "done" },
    "getBalance" => { "balance" => { "merchant" => [{ "currency" => "USDT", "balance" => "12.5" }] } }
  }.freeze

  attr_reader :calls

  def initialize
    @calls = []
  end

  def call(request, timeout:) # rubocop:disable Lint/UnusedMethodArgument
    @calls << request
    op, route = route_for(request.method, URI.parse(request.url).path)
    if route.bare
      return Oblodai::HTTP::Response.new(status: 200, headers: { "content-type" => "application/pdf" },
                                         body: "%PDF-1.7", url: request.url)
    end

    result = Samples.result(op)
    shape = SHAPES.fetch(op, {})
    result = route.paged? ? result.merge("items" => result["items"].map { |i| i.merge(shape) }) : result.merge(shape)
    Oblodai::HTTP::Response.new(status: 200, headers: { "content-type" => "application/json" },
                                body: JSON.generate("state" => 0, "result" => result), url: request.url)
  end

  private

  def route_for(method, path)
    Oblodai::Generated::ROUTES.each do |op, route|
      pattern = /\A#{route.path.split(/\{[^}]+\}/, -1).map { |part| Regexp.escape(part) }.join("[^/]+")}\z/
      return [op, route] if route.method == method && pattern.match?(path)
    end
    raise "the snippet calls a route the API does not have: #{method} #{path}"
  end
end
