# frozen_string_literal: true

# Minimal valid bodies for the generated models, read off the generated source the way a reader
# would: every `from_h` line names a field, whether it is required (`data.fetch`) and its type. A
# spec asks for the answer of an operation (`Samples.result("createPayment", "uuid" => "u")`) and
# gets a body its generated method parses, so a renamed model or a new required field is picked up
# without editing the specs.
module Samples
  GENERATED = File.expand_path("../../lib/oblodai/generated", __dir__)
  FIELD = /^\s+\w+: Generated::Codec\.read\(data(?:\.fetch\("([^"]+)"\)|\["([^"]+)"\]), (.+)\),?$/
  CLASS = /^    class (\w+) < Generated::Model$/
  UNION = /^    module (\w+)$/
  VARIANTS = /^      VARIANTS = \[(.+)\]\.freeze$/

  module_function

  # @return [Hash{String => Hash{String => Array(Boolean, String)}}] model => json => [required, type]
  def models
    @models ||= begin
      out = {}
      current = nil
      File.foreach(File.join(GENERATED, "models.rb")) do |line|
        if (m = CLASS.match(line))
          current = out[m[1]] = {}
        elsif (m = UNION.match(line))
          current = nil
          unions[m[1]] = nil
          @union = m[1]
        elsif (m = VARIANTS.match(line)) && @union
          unions[@union] = m[1].split(", ")
        elsif current && (m = FIELD.match(line))
          current[m[1] || m[2]] = [!m[1].nil?, m[3]]
        end
      end
      out
    end
  end

  # @return [Hash{String => Array<String>}] oneOf module => variant models
  def unions
    @unions ||= {}
  end

  # @return [Hash{String => String, nil}] operationId => model its method parses the result with
  def parsers
    @parsers ||= begin
      out = {}
      op = nil
      File.foreach(File.join(GENERATED, "resources.rb")) do |line|
        if (m = /Generated::ROUTES\.fetch\("(\w+)"\)/.match(line))
          op = m[1]
        elsif op && (m = /^\s+parse: (?:Models::(\w+)\.method\(:from_h\)|nil)$/.match(line))
          out[op] = m[1]
          op = nil
        end
      end
      out
    end
  end

  # A body with every required field of `model` (a model or oneOf name), plus `overrides`.
  # @return [Hash{String => Object}]
  def body(model, overrides = {})
    models # parse once, unions included
    return body(unions.fetch(model).first, overrides) if unions.key?(model)

    fields = models.fetch(model) { raise "no generated model #{model}" }
    out = fields.select { |_, (required, _)| required }.to_h { |json, (_, type)| [json, value(type)] }
    # Required but nullable: always sent, as null here.
    Oblodai::Models.const_get(model)::REQUIRED.each { |json| out[json] = nil unless out.key?(json) }
    out.merge(overrides.transform_keys(&:to_s))
  end

  # The `result` a successful call of `operation_id` answers with: its model's body, or a page of
  # one such item for a paged list.
  # @return [Hash{String => Object}]
  def result(operation_id, overrides = {})
    route = Oblodai::Generated::ROUTES.fetch(operation_id)
    model = parsers.fetch(operation_id) { raise "no generated method calls #{operation_id}" }
    return overrides if model.nil?
    return body(model, overrides) unless route.paged?

    { "items" => [body(model, overrides)],
      "paginate" => { "total" => 1, "per_page" => 50, "offset" => 0, "has_pages" => false } }
  end

  def value(type)
    case type
    when ":string" then "x"
    when ":decimal" then "1"
    when ":integer" then 1
    when ":float" then 1.5
    when ":boolean" then false
    when ":any", /\A(?:%i\[map |\[:map, )/ then {}
    when /\A(?:%i\[array |\[:array, )/ then []
    else body(type)
    end
  end
end
