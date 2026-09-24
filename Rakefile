# frozen_string_literal: true

require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec) do |task|
  task.pattern = "spec/{unit,contract,conformance}/**/*_spec.rb"
end

desc "Run the live suites against a real core (OBLODAI_LIVE_URL, default http://127.0.0.1:8095)"
RSpec::Core::RakeTask.new("spec:live") do |task|
  ENV["OBLODAI_LIVE_URL"] ||= "http://127.0.0.1:8095"
  task.pattern = "spec/live/**/*_spec.rb"
end

RuboCop::RakeTask.new

desc "Generate the YARD reference into doc/ (development dependency: yard)"
task :yard do
  sh "yard doc --output-dir doc --no-progress lib"
end

desc "Build the gem into pkg/ and check it carries the runtime, the generated code and the docs"
task :package do
  require "rubygems/package"
  require_relative "lib/oblodai/version"
  path = "pkg/oblodai-#{Oblodai::VERSION}.gem"
  mkdir_p "pkg"
  sh "gem build oblodai.gemspec --output #{path} --quiet"
  files = Gem::Package.new(path).contents
  wanted = %w[lib/oblodai.rb lib/oblodai/generated/resources.rb lib/oblodai/generated/models.rb
              lib/oblodai/core/transport.rb lib/oblodai/webhooks.rb names.lock README.md MIGRATION-2.0.md
              AGENTS.md examples/accept_payment.rb]
  missing = wanted - files
  abort "package: #{path} is missing #{missing.join(", ")}" unless missing.empty?
  stray = files.grep(%r{\A(spec|contract|vendor)/})
  abort "package: #{path} carries #{stray.first(3).join(", ")}" unless stray.empty?
  puts "package: #{path} (#{files.size} files) carries the runtime, the generated code and the docs"
end

desc "Everything CI runs in Ruby: lint, unit, contract and conformance specs, the gem"
task ci: %i[rubocop spec package]

task default: :ci
