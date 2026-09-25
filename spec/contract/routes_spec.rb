# frozen_string_literal: true

# Route coverage: every operation of the contract has exactly one SDK method behind it, wired to the
# right METHOD and path, signed the way the core's gate expects and carrying an Idempotency-Key
# exactly where the core deduplicates. The ledger (spec/support/coverage.rb) is read off the
# generated namespaces.
RSpec.describe "route coverage" do
  routes = Oblodai::Generated::ROUTES
  names_lock = File.readlines(File.expand_path("../../names.lock", __dir__), chomp: true)

  it "reaches every operation from exactly one method" do
    expect(Coverage.ledger.keys.sort).to eq(routes.keys.sort)
  end

  it "is what names.lock pins" do
    expect(Coverage.ledger.values.map { |ns, name| "#{ns}.#{name}" }.sort).to eq(names_lock.sort)
  end

  it "is the operation list of the backend's openapi.json" do
    spec = backend_spec
    skip "backend openapi.json not found (set OBLODAI_BACKEND)" if spec.nil?

    declared = spec["paths"].flat_map do |path, item|
      item.filter_map { |verb, op| [op["operationId"], verb.upcase, path] if op.is_a?(Hash) && op["operationId"] }
    end
    expect(routes.values.map { |r| [r.operation_id, r.method, r.path] }).to match_array(declared)
    retry_safe = declared.select { |_, verb, path| spec.dig("paths", path, verb.downcase, "x-retry-safe") == true }
    expect(routes.select { |_, r| r.safe }.keys).to match_array(retry_safe.map(&:first))
  end

  it "names only error codes the contract catalogue declares" do
    named = Hash.new { |h, k| h[k] = [] }
    Dir["lib/**/*.rb", "*.md"].reject { |path| path.include?("/generated/") }.each do |path|
      collecting = false
      File.readlines(path).each_with_index do |line, index|
        comment = path.end_with?(".md") || line.match?(/^\s*#/)
        collecting = false unless comment
        collecting = true if comment && line.match?(/[Cc]odes worth (branching on|handling)/)
        next unless collecting

        collecting = false if line.strip == "#" || line.strip.empty?
        line.scan(/`([a-z][a-z0-9_]*\.[a-z][a-z0-9_]*)`/) { |(code)| named[code] << "#{path}:#{index + 1}" }
      end
    end

    # The SDK's own families are not gateway codes and are not in the catalogue.
    gateway = named.reject { |code, _| code.start_with?("sdk.", "transport.", "webhook.") }
    expect(gateway.size).to be > 5
    unknown = gateway.except(*Oblodai::Enums::ErrorCode::VALUES)
    expect(unknown).to be_empty,
                       "documented codes the core does not declare: " \
                       "#{unknown.map { |c, where| "#{c} (#{where.join(", ")})" }.join("; ")}"
  end

  routes.each do |operation_id, route|
    it "#{operation_id} (#{route.key}) is wired to the right method, path, auth gate and idempotency" do
      answer = if route.bare
                 { status: 200, body: "%PDF", headers: { "content-type" => "application/pdf" } }
               else
                 FakeHTTP.ok_for(operation_id)
               end
      http = FakeHTTP.new([answer])
      client = Oblodai::Client.new(public_id: "pk", secret: "s", admin_token: "adm",
                                   base_url: "https://api.test", http: http, env: {})
      result = Coverage.call(client, operation_id)
      result.first_page if result.is_a?(Oblodai::Page)

      expect(http.calls.size).to eq(1)
      call = http.calls.first
      expect(call.verb).to eq(route.method)
      expect(call.path).to match(/\A#{route.path.gsub(/\{[a-z_]+\}/, "[^/]+")}\z/)
      expect(call.body).to be_nil if route.method == "GET"

      # One API key signs every signed route; the admin token appears on the onboarding routes and
      # nowhere else; a public route carries no credential at all.
      case route.auth
      when :public
        expect(call.headers).not_to have_key(SIGNING::HEADER_SIGNATURE.downcase)
        expect(call.headers).not_to have_key(SIGNING::HEADER_PUBLIC_ID.downcase)
        expect(call.headers).not_to have_key("x-admin-token")
      when :onboard
        expect(call.headers).not_to have_key(SIGNING::HEADER_SIGNATURE.downcase)
        expect(call.headers["x-admin-token"]).to eq("adm")
      else
        expect(route.auth).to eq(:key)
        expect(call.headers[SIGNING::HEADER_PUBLIC_ID.downcase]).to eq("pk")
        expect(call.headers[SIGNING::HEADER_SIGNATURE.downcase]).to match(/\A[0-9a-f]{64}\z/)
        expect(call.headers).not_to have_key("x-admin-token")
      end

      if route.idempotent
        expect(call.headers[SIGNING::HEADER_IDEMPOTENCY_KEY.downcase]).to match(/\A[0-9a-f-]{36}\z/)
      else
        expect(call.headers).not_to have_key(SIGNING::HEADER_IDEMPOTENCY_KEY.downcase)
      end

      if route.bare
        expect(result).to be_a(Oblodai::FileResult)
      elsif Oblodai::Generated::LRO.key?(operation_id)
        expect(result).to be_a(Oblodai::Job)
      elsif route.paged?
        expect(result).to be_a(Oblodai::Page)
      elsif Samples.parsers[operation_id]
        model = Oblodai::Models.const_get(Samples.parsers[operation_id])
        variants = model.is_a?(Class) ? [model] : model::VARIANTS
        expect(variants).to include(result.class)
      end
    end
  end
end
