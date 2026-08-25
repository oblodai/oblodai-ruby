# frozen_string_literal: true

require "json"

# Loads the contract snapshot shipped in contract/: the route registry and vectors, the golden
# response bodies recorded from a live core, the error samples and the real signed webhook
# deliveries. Nothing here is generated — the files are the core's own export.
module Fixtures
  DIR = File.expand_path("../../contract", __dir__)

  module_function

  # @return [Hash] the whole contract.json
  def contract
    @contract ||= JSON.parse(File.read(File.join(DIR, "contract.json")))
  end

  # @return [Hash{String => Hash}] golden bodies by route key
  def fixtures
    @fixtures ||= Dir[File.join(DIR, "fixtures", "*.json")].each_with_object({}) do |path, out|
      body = JSON.parse(File.read(path))
      out[body["route"]] = body
    end
  end

  # @param route [String]
  # @return [Hash]
  def fixture(route)
    fixtures.fetch(route) { raise "no fixture for #{route}" }
  end

  # The recorded success `result` for a route.
  # @raise [RuntimeError] when the recording was a refusal
  def result_of(route)
    fx = fixture(route)
    raise "fixture for #{route} is a refusal (#{fx["status"]})" unless (200..299).cover?(fx["status"])

    fx.dig("response", "result")
  end

  # @return [Array<Hash>] real signed webhook deliveries (headers + raw body bytes)
  def webhook_samples
    @webhook_samples ||= JSON.parse(File.read(File.join(DIR, "webhook-samples.json")))
  end

  # @return [Hash{String => Hash}] error envelope samples by code
  def error_samples
    @error_samples ||= Dir[File.join(DIR, "errors", "*.json")].to_h do |path|
      [File.basename(path, ".json"), JSON.parse(File.read(path))]
    end
  end

  # @return [Array<String>] "METHOD /path" of every merchant-facing route the core declares
  def declared_routes
    contract["routes"]
      .reject { |r| %r{^/(healthz|readyz|docs|openapi\.json|internal)}.match?(r["path"]) }
      .map { |r| "#{r["method"]} #{r["path"]}" }
  end
end
