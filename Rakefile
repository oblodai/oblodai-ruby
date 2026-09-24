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

desc "Everything CI runs in Ruby: lint, unit, contract and conformance specs"
task ci: %i[rubocop spec]

task default: :ci
