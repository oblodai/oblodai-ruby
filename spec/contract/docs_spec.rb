# frozen_string_literal: true

# Documentation is a promise the code has to keep. These checks are the cheap half of keeping it:
# every snippet parses, and every list the prose gives (options, environment variables, key kinds)
# is compared with the code that implements it. The Russian README is held to the same code: a
# translation translates prose, never a snippet.
ENGLISH_README = "README.md"
RUSSIAN_README = "README.ru.md"
DOCS = [ENGLISH_README, RUSSIAN_README, "AGENTS.md", "MIGRATION-1.3.md", "CHANGELOG.md"].freeze

RSpec.describe "documentation" do
  def ruby_blocks(path)
    File.read(path).scan(/```ruby\n(.*?)```/m).flatten
  end

  # Every fenced block of a file, as [language, body] pairs, in source order.
  def fenced_blocks(path)
    File.read(path).scan(/```([a-z]*)\n(.*?)```/m)
  end

  def headings(path, level)
    File.read(path).lines.grep(/\A#{"#" * level} \S/)
  end

  it "has only snippets Ruby can parse" do
    DOCS.each do |path|
      ruby_blocks(path).each_with_index do |snippet, index|
        # Sinatra-style snippets use bare block DSL; wrapping keeps them parseable without running.
        expect { RubyVM::AbstractSyntaxTree.parse(snippet) }
          .not_to(raise_error, "#{path}: ruby block ##{index + 1} does not parse")
      end
    end
    expect(ruby_blocks(ENGLISH_README).size).to be >= 5
  end

  it "shows the same code in the English and the Russian README" do
    english = fenced_blocks(ENGLISH_README)
    russian = fenced_blocks(RUSSIAN_README)
    expect(russian.size).to eq(english.size)
    english.zip(russian).each_with_index do |(en, ru), index|
      expect(ru).to eq(en), "code block ##{index + 1} differs between the READMEs " \
                            "(a translation must not translate code)"
    end
  end

  it "carries every section of the English README into the Russian one" do
    (2..3).each do |level|
      expect(headings(RUSSIAN_README, level).size).to eq(headings(ENGLISH_README, level).size),
                                                      "the translation must carry every H#{level} section"
    end
  end

  it "lists exactly the per-call options the resource layer accepts" do
    documented = File.read(ENGLISH_README)[/method accepts (.*?);/m].scan(/`([a-z_]+):`/).flatten
    expect(documented.map(&:to_sym)).to match_array(Oblodai::Resources::Base::OPTION_KEYS)
    from_agents = File.read("AGENTS.md")[/The same keyword list also accepts (.*?)\./m]
                      .scan(/`([a-z_]+):`/).flatten
    expect(from_agents.map(&:to_sym)).to match_array(Oblodai::Resources::Base::OPTION_KEYS)
  end

  it "names exactly the environment variables the config reads" do
    read_by_config = File.read("lib/oblodai/config.rb").scan(/env\["(OBLODAI_[A-Z_]+)"\]/).flatten.uniq
    named_in_readme = File.read(ENGLISH_README).scan(/`(OBLODAI_[A-Z_]+)/).flatten.uniq
    expect(named_in_readme).to match_array(read_by_config)
  end

  it "describes the one auth vocabulary the contract actually has" do
    expect(Oblodai::Contract::ROUTES.values.map(&:auth).uniq).to match_array(%i[public key onboard])
  end

  it "promises no second key anywhere the reader would look for one" do
    # Every trace of the old payment/payout split: a credential option, an environment variable, a
    # per-call preference. A doc that still offers one is a doc that sends a reader looking for a
    # key the gateway stopped minting.
    gone = [/payout_public_id/, /payout_secret/, /OBLODAI_PAYOUT/, /prefer_payout_key/,
            /payout key/i, /payment key/i, /выплатн\w* ключ/i, /платёжн\w* ключ/i]
    (DOCS + Dir["examples/*.rb", "examples/README.md", "lib/**/*.rb"]).each do |path|
      next if path.end_with?("contract/enums.rb") # the generated catalogue is the core's own words
      next if path == "CHANGELOG.md" # the one place that must name them: to record their removal

      text = File.read(path)
      gone.each { |pattern| expect(text).not_to match(pattern), "#{path} still offers #{pattern}" }
    end
  end

  it "keeps the legacy key-kind error explained exactly once, in each language" do
    # `merchant.wrong_key_kind` left the catalogue with the split keys, so it may not be listed as a
    # code to branch on — but a merchant still holding an old pair deserves one sentence about it.
    [ENGLISH_README, RUSSIAN_README, "MIGRATION-1.3.md"].each do |path|
      expect(File.read(path).scan("merchant.wrong_key_kind").size).to eq(1), "#{path}: say it once"
    end
    expect(File.read(ENGLISH_README)).to match(/oblodai_pk_.*oblodai_wk_/m)
    expect(Oblodai::Enums::ERROR_CODES).not_to include("merchant.wrong_key_kind")
  end

  it "states the batch limits the gateway enforces" do
    readme = File.read(ENGLISH_README)
    expect(readme).to include("`payouts.mass` at 100 elements", "`payout_links.batch` at 500")
    expect(File.read("lib/oblodai/resources/payouts.rb")).to include("SYNCHRONOUS batch (at most 100)")
    expect(File.read("lib/oblodai/resources/links.rb")).to include("at most 500 links")
  end

  it "counts the routes and error codes the contract actually has" do
    routes = Oblodai::Contract::ROUTES.size
    codes = Oblodai::Enums::ERROR_CODES.size
    expect(routes).to eq(107)
    expect(codes).to eq(469)
    DOCS.each do |path|
      text = File.read(path)
      text.scan(/(\d{3}) (?:error codes|кодов ошибок)/).flatten.each { |n| expect(n.to_i).to eq(codes) }
      text.scan(/ROUTES` \((\d+) (?:routes|маршрутов)/).flatten.each { |n| expect(n.to_i).to eq(routes) }
      text.scan(/(\d+) (?:routes|маршрутов) — the whole|(\d+) маршрутов — вся/).flatten.compact
          .each { |n| expect(n.to_i).to eq(routes) }
    end
  end

  it "documents the error classes the SDK can actually raise" do
    named = File.read(ENGLISH_README).scan(/`(\w+Error)`/).flatten.uniq
    named.each { |klass| expect(Oblodai.const_defined?(klass)).to be(true), "README names #{klass}" }
    %w[WebhookPayloadError ContractError ConfigError SignatureError].each do |klass|
      expect(named).to include(klass)
    end
  end
end
