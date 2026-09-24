# frozen_string_literal: true

# The documents a reader trusts before the code: they must name what the SDK actually has.
RSpec.describe "documentation" do
  root = File.expand_path("../..", __dir__)
  read = ->(name) { File.read(File.join(root, name)) }
  locked = File.readlines(File.join(root, "names.lock"), chomp: true)
  # The public names of 2.0.0, frozen once: MIGRATION-2.0.md maps 1.x to these, and later methods
  # (added to names.lock by the generator) are not part of that migration.
  names20 = File.readlines(File.join(root, "names.2.0.txt"), chomp: true)

  it "MIGRATION-2.0.md maps every name of 2.0" do
    migration = read.call("MIGRATION-2.0.md")
    names20.each { |name| expect(migration).to include("| `#{name}` |"), name }
    expect(migration).to include("## Method names (#{names20.size} methods)")
    expect(names20 - locked).to be_empty, "a 2.0 name left names.lock: that is a breaking change"
  end

  it "releases the version the gem declares" do
    expect(Oblodai::VERSION).to eq(Gem::Specification.load(File.join(root, "oblodai.gemspec")).version.to_s)
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

  it "locks and documents every method the SDK has (both written by the generator)" do
    names = Oblodai::Resources.constants.filter_map do |const|
      cls = Oblodai::Resources.const_get(const)
      next unless cls.is_a?(Class) && cls < Oblodai::Resources::Base

      resource = const.to_s.gsub(/([a-z\d])([A-Z])/, "\\1_\\2").downcase
      cls.public_instance_methods(false).map { |m| "#{resource}.#{m}" }
    end.flatten
    expect(locked.sort).to eq(names.sort)
    expect(locked.size).to eq(Oblodai::Generated::ROUTES.size)
    %w[README.md README.ru.md].each do |doc|
      section = read.call(doc)[%r{<!-- sdkgen:methods -->(.*)<!-- /sdkgen:methods -->}m, 1]
      expect(section).not_to be_nil, doc
      expect(section).to match(/, #{locked.size} (methods|метод)/), doc
      locked.group_by { |n| n.split(".").first }.each do |resource, methods|
        row = section[/^\| `#{resource}` \|.*$/]
        expect(row).not_to be_nil, "#{doc}: #{resource}"
        methods.each { |n| expect(row).to include("`#{n.split(".").last}`"), "#{doc}: #{n}" }
      end
    end
  end
end
