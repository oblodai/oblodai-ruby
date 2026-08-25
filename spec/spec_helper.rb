# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "oblodai"
require_relative "support/fake_http"
require_relative "support/fixtures"

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :defined
  config.filter_run_excluding(live: true) unless ENV["OBLODAI_LIVE_URL"]
end

# Credentials every unit spec builds its client with.
TEST_CREDENTIALS = {
  public_id: "pk_test_1", secret: "secret-1", base_url: "https://api.test",
  retry_policy: { base_delay_ms: 1, max_delay_ms: 2 }
}.freeze

# @return [Oblodai::Client] a client wired to a {FakeHTTP}
def client_with(http, **overrides)
  Oblodai::Client.new(**TEST_CREDENTIALS, http: http, **overrides)
end
