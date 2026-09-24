# frozen_string_literal: true

require "stringio"
require "tmpdir"

# The README code runs: every ```ruby block of both READMEs executes against a scripted gateway.
# Blocks of one README run in order in one binding, the way a reader pastes them one after another
# (the quick start makes `client`, later blocks use it), so a renamed method, argument or field
# breaks this spec.
RSpec.describe "README" do
  root = File.expand_path("../..", __dir__)
  blocks = ->(doc) { File.read(File.join(root, doc)).scan(/```ruby\n(.*?)```/m).map(&:first) }

  around do |example|
    saved = ENV.to_h.slice("OBLODAI_PUBLIC_ID", "OBLODAI_SECRET", "OBLODAI_BASE_URL")
    ENV["OBLODAI_PUBLIC_ID"] = "readme"
    ENV["OBLODAI_SECRET"] = "s" * 32
    ENV.delete("OBLODAI_BASE_URL")
    example.run
  ensure
    %w[OBLODAI_PUBLIC_ID OBLODAI_SECRET OBLODAI_BASE_URL].each { |k| saved.key?(k) ? ENV[k] = saved[k] : ENV.delete(k) }
  end

  it "shows the same code in the English and the Russian README" do
    expect(blocks.call("README.md").size).to be >= 10
    expect(blocks.call("README.ru.md")).to eq(blocks.call("README.md"))
  end

  it "has no Float amount in any snippet" do
    blocks.call("README.md").each { |block| expect(block).not_to match(/amount: \d+\.\d+/) }
  end

  %w[README.md README.ru.md].each do |doc|
    it "#{doc}: every ruby block runs, and the webhook receiver it defines answers right" do
      gateway = Gateway.new
      allow(Oblodai::HTTP::NetHTTPAdapter).to receive(:new).and_return(gateway)
      scope = Object.new
      bind = scope.instance_eval { binding }
      out = StringIO.new
      Dir.mktmpdir do |dir|
        Dir.chdir(dir) do
          $stdout = out
          blocks.call(doc).each_with_index do |source, index|
            eval(source, bind, "#{doc}##{index}") # rubocop:disable Security/Eval
          rescue StandardError, ScriptError => e
            raise "#{doc} block ##{index} fails: #{e.class}: #{e.message}\n#{source}"
          end
        ensure
          $stdout = STDOUT
        end
      end
      expect(gateway.calls).not_to be_empty

      # The webhook block defines a receiver; drive it with one signed delivery and one forgery.
      body = JSON.generate(Samples.body("PaymentWebhook", "type" => "payment", "uuid" => "u", "status" => "paid"))
      ts = Time.now.to_i
      headers = { "X-Webhook-Timestamp" => ts.to_s,
                  "X-Webhook-Signature" => Oblodai::Signing.sign_webhook("whsec-readme", ts, body) }
      $stdout = out
      expect(scope.send(:receive, body, headers, "whsec-readme")).to eq(200)
      expect(scope.send(:receive, "#{body} ", headers, "whsec-readme")).to eq(401)
    ensure
      $stdout = STDOUT
    end
  end
end
