# frozen_string_literal: true

# The documents a reader trusts before the code: they must name what the SDK actually has.
RSpec.describe "documentation" do
  root = File.expand_path("../..", __dir__)
  read = ->(name) { File.read(File.join(root, name)) }
  locked = File.readlines(File.join(root, "names.lock"), chomp: true)

  it "MIGRATION-2.0.md maps every locked name" do
    migration = read.call("MIGRATION-2.0.md")
    locked.each { |name| expect(migration).to include("| `#{name}` |"), name }
    expect(migration).to include("## Method names (#{locked.size} methods)")
  end

  it "releases the version the gem declares" do
    expect(Oblodai::VERSION).to eq("2.0.0")
    expect(read.call("CHANGELOG.md")[/^## \[([^\]]+)\]/, 1]).to eq(Oblodai::VERSION)
    %w[README.md README.ru.md].each do |doc|
      expect(read.call(doc)).to include("gem-oblodai%20#{Oblodai::VERSION}")
    end
  end

  it "states the minimum Ruby the gemspec requires" do
    spec = Gem::Specification.load(File.join(root, "oblodai.gemspec"))
    expect(spec.required_ruby_version.to_s).to eq(">= 3.2")
    %w[README.md README.ru.md AGENTS.md].each { |doc| expect(read.call(doc)).to include("Ruby ≥ 3.2") }
    expect(spec.runtime_dependencies.map(&:name)).to eq(["bigdecimal"])
  end

  it "names exactly the environment variables the config reads" do
    source = Dir[File.join(root, "lib/oblodai/**/*.rb")].map { |f| File.read(f) }.join
    read_vars = source.scan(/env\["(OBLODAI_[A-Z_]+)"\]/).flatten.uniq.sort
    %w[README.md README.ru.md].each do |doc|
      documented = read.call(doc).scan(/^\| `(OBLODAI_[A-Z_]+)`/).flatten.sort
      expect(documented).to eq(read_vars), doc
    end
  end

  it "lists the call options every generated method takes" do
    options = Oblodai::RequestOptions.members.map(&:to_s)
    expect(options).to eq(%w[idempotency_key timeout max_retries extra_headers request_id])
    %w[README.md README.ru.md AGENTS.md MIGRATION-2.0.md].each do |doc|
      options.each { |option| expect(read.call(doc)).to include("`#{option}:`"), "#{doc}: #{option}" }
    end
  end

  it "counts the methods the SDK has" do
    expect(locked.size).to eq(Oblodai::Generated::ROUTES.size)
    expect(read.call("README.md")).to include("#{locked.size} methods")
    expect(read.call("README.ru.md")).to include("#{locked.size} методов")
  end
end
