# frozen_string_literal: true

# Documentation is a promise the code has to keep. These checks are the cheap half of keeping it:
# every snippet parses, and every list the prose gives (options, environment variables, key kinds)
# is compared with the code that implements it.
DOCS = %w[README.md AGENTS.md MIGRATION-1.3.md CHANGELOG.md].freeze

RSpec.describe "documentation" do
  def ruby_blocks(path)
    File.read(path).scan(/```ruby\n(.*?)```/m).flatten
  end

  it "has only snippets Ruby can parse" do
    DOCS.each do |path|
      ruby_blocks(path).each_with_index do |snippet, index|
        # Sinatra-style snippets use bare block DSL; wrapping keeps them parseable without running.
        expect { RubyVM::AbstractSyntaxTree.parse(snippet) }
          .not_to(raise_error, "#{path}: ruby block ##{index + 1} does not parse")
      end
    end
    expect(ruby_blocks("README.md").size).to be >= 5
  end

  it "lists exactly the per-call options the resource layer accepts" do
    documented = File.read("README.md")[/method accepts (.*?);/m].scan(/`([a-z_]+):`/).flatten
    expect(documented.map(&:to_sym)).to match_array(Oblodai::Resources::Base::OPTION_KEYS)
    from_agents = File.read("AGENTS.md")[/The same keyword list also accepts (.*?)\./m]
                      .scan(/`([a-z_]+):`/).flatten
    expect(from_agents.map(&:to_sym)).to match_array(Oblodai::Resources::Base::OPTION_KEYS)
  end

  it "names exactly the environment variables the config reads" do
    read_by_config = File.read("lib/oblodai/config.rb").scan(/env\["(OBLODAI_[A-Z_]+)"\]/).flatten.uniq
    named_in_readme = File.read("README.md").scan(/`(OBLODAI_[A-Z_]+)/).flatten.uniq
    expect(named_in_readme).to match_array(read_by_config)
  end

  it "claims the right routes need the payout key" do
    payout_routes = Oblodai::Contract::ROUTES.select { |_, spec| spec.auth == :payout }.keys
    claimed = %w[
      /v1/payout /v1/payment/refund /v1/payment/resolve /v1/refund/batch /v1/transfer /v1/split
      /v1/wallet/blocked-address-refund /v1/auto-withdraw /v1/api-allowlist /v1/webhooks/rotate-secret
      /v1/sandbox/faucet /v1/sandbox/reset /v1/test-webhook/payout
    ]
    unclaimed = payout_routes.reject { |key| claimed.any? { |prefix| key.include?(prefix) } }
    expect(unclaimed).to be_empty, "README/AGENTS do not mention these payout-key routes: #{unclaimed}"
  end

  it "states the batch limits the gateway enforces" do
    readme = File.read("README.md")
    expect(readme).to include("`payouts.mass` at 100 elements", "`payout_links.batch` at 500")
    expect(File.read("lib/oblodai/resources/payouts.rb")).to include("SYNCHRONOUS batch (at most 100)")
    expect(File.read("lib/oblodai/resources/links.rb")).to include("at most 500 links")
  end

  it "counts the routes and error codes the contract actually has" do
    routes = Oblodai::Contract::ROUTES.size
    codes = Oblodai::Enums::ERROR_CODES.size
    expect(routes).to eq(107)
    expect(codes).to eq(471)
    DOCS.each do |path|
      text = File.read(path)
      text.scan(/(\d{3}) error codes/).flatten.each { |n| expect(n.to_i).to eq(codes) }
      text.scan(/ROUTES` \((\d+) routes/).flatten.each { |n| expect(n.to_i).to eq(routes) }
    end
  end

  it "documents the error classes the SDK can actually raise" do
    named = File.read("README.md").scan(/`(\w+Error)`/).flatten.uniq
    named.each { |klass| expect(Oblodai.const_defined?(klass)).to be(true), "README names #{klass}" }
    %w[WebhookPayloadError ContractError ConfigError SignatureError].each do |klass|
      expect(named).to include(klass)
    end
  end
end
