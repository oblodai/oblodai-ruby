# frozen_string_literal: true

require "json"

# Loads the recordings kept in contract/ as test data (the gem does not ship them): the golden
# response bodies recorded from a live core, the error samples and the real signed webhook
# deliveries. Signing vectors are not recorded here: {SigningVectors} reads them from the spec.
module Fixtures
  DIR = File.expand_path("../../contract", __dir__)

  module_function

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
end

# The signing vectors of `x-oblodai-signing` in the backend's openapi.json — the one source the
# generator and the conformance suite read too. Empty when the backend checkout is absent.
module SigningVectors
  module_function

  # @return [Hash] x-oblodai-signing, or {} without the backend spec
  def signing
    @signing ||= backend_spec&.fetch("x-oblodai-signing") || {}
  end

  # @return [Array<Hash>]
  def request
    signing.fetch("request_vectors", [])
  end

  # @return [Array<Hash>]
  def webhook
    signing.dig("webhook", "vectors") || []
  end
end
