# frozen_string_literal: true

require_relative "lib/oblodai/version"

Gem::Specification.new do |spec|
  spec.name = "oblodai"
  spec.version = Oblodai::VERSION
  spec.authors = ["Oblodai"]
  spec.email = ["dev@oblodai.com"]

  spec.summary = "Official Ruby SDK for the Oblodai crypto payment gateway"
  spec.description = "Invoices, payouts, refunds, payout links, static wallets, webhooks and " \
                     "documents — the whole Oblodai merchant API, generated from the gateway's " \
                     "OpenAPI contract. Keyword arguments, BigDecimal amounts, frozen models, " \
                     "safe retries, waiters for batches and document jobs."
  spec.homepage = "https://oblodai.com"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => "https://github.com/oblodai/oblodai-ruby",
    "changelog_uri" => "https://github.com/oblodai/oblodai-ruby/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "https://github.com/oblodai/oblodai-ruby/issues",
    "documentation_uri" => "https://docs.oblodai.com",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir[
    "lib/**/*.rb",
    "examples/*.rb",
    "names.lock",
    "README.md", "README.ru.md", "CHANGELOG.md", "MIGRATION-2.0.md", "MIGRATION-1.3.md", "AGENTS.md", "LICENSE"
  ]
  spec.require_paths = ["lib"]

  # Amounts are BigDecimal; from Ruby 3.4 on it is a bundled gem, no longer part of the default set.
  spec.add_dependency "bigdecimal", ">= 3.1"
end
