# frozen_string_literal: true

require "rspec/core/rake_task"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec) do |task|
  task.pattern = "spec/{unit,contract}/**/*_spec.rb"
end

desc "Run the live suites against a real core (OBLODAI_LIVE_URL, default http://127.0.0.1:8095)"
RSpec::Core::RakeTask.new("spec:live") do |task|
  ENV["OBLODAI_LIVE_URL"] ||= "http://127.0.0.1:8095"
  task.pattern = "spec/live/**/*_spec.rb"
end

RuboCop::RakeTask.new

GENERATED = %w[routes.rb enums.rb requests.rb].map { |f| File.join("lib", "oblodai", "contract", f) }.freeze

desc "Regenerate lib/oblodai/contract from contract/contract.json"
task :codegen do
  ruby "script/codegen.rb"
end

desc "Fail when the committed contract code is not what codegen produces"
task :drift do
  before = GENERATED.to_h { |path| [path, File.read(path)] }
  ruby "script/codegen.rb"
  drifted = GENERATED.reject { |path| File.read(path) == before[path] }
  unless drifted.empty?
    abort "contract drift: #{drifted.join(", ")} differ from contract/contract.json — " \
          "commit the regenerated files"
  end
  puts "drift: #{GENERATED.size} generated files are in sync with contract/contract.json"
end

desc "Generate the YARD reference into doc/ (development dependency: yard)"
task :yard do
  sh "yard doc --output-dir doc --no-progress lib"
end

desc "Everything CI runs: lint, contract drift, unit and contract specs"
task ci: %i[rubocop drift spec]

task default: :ci
