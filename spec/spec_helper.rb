# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "oblodai"
require_relative "support/samples"
require_relative "support/fake_http"
require_relative "support/coverage"
require_relative "support/gateway"
require_relative "support/fixtures"

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :defined
  config.filter_run_excluding(live: true) unless ENV["OBLODAI_LIVE_URL"]
end

# The generated signing protocol: specs name headers by it, never by literal, so a header the core
# renames reaches them by regeneration alone.
SIGNING = Oblodai::Generated::SigningProtocol

# Credentials every unit spec builds its client with.
TEST_CREDENTIALS = {
  public_id: "pk_test_1", secret: "secret-1", base_url: "https://api.test",
  retry_policy: { base_delay_ms: 1, max_delay_ms: 2 }
}.freeze

# @return [Oblodai::Client] a client wired to a {FakeHTTP}
def client_with(http, **overrides)
  Oblodai::Client.new(**TEST_CREDENTIALS, http: http, **overrides)
end

# Where the specs read the contract and the conformance suite from: OBLODAI_BACKEND when set, else
# the vendored contract/snapshot (laid out like a backend checkout, kept equal to the backend by
# script/check_generated.sh) — never a guessed sibling checkout, which may sit at another contract.
# @return [String]
def contract_root
  ENV.fetch("OBLODAI_BACKEND") { File.expand_path("../contract/snapshot", __dir__) }
end

# The contract's openapi.json, or nil when absent.
# @return [Hash, nil]
def backend_spec
  path = File.join(contract_root, "services", "core", "api", "openapi.json")
  File.file?(path) ? JSON.parse(File.read(path)) : nil
end
