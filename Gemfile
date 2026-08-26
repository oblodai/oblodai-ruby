# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :development, :test do
  gem "rake", "~> 13.0"
  gem "rspec", "~> 3.13"
  gem "rubocop", "~> 1.60"
  # Documentation for `rake yard`; the gem itself has no runtime dependencies.
  gem "yard", "~> 0.9"
end

group :development do
  # examples/webhook_receiver.rb only. WEBrick left the standard library in Ruby 3.0, so it is a
  # development dependency here rather than something the example can assume is installed.
  gem "webrick", "~> 1.8"
end
