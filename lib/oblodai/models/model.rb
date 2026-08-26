# frozen_string_literal: true

module Oblodai
  module Models
    # What a redacted field renders as in every automatic rendering of a model.
    REDACTED = "[redacted]"

    # Wire models. Every response body the core documents has a model here: a frozen value object
    # whose attributes are named EXACTLY as the wire names them (snake_case, no renaming), with the
    # English description of each field in its YARD doc.
    #
    # - Amounts are decimal strings ({Oblodai::Money}) — never floats.
    # - `to_h` gives the wire shape back, including any field newer than this release (unknown keys
    #   are kept, not dropped, so an integration never loses data the core started sending).
    # - `keys` on the class is the declared key set; the contract suite compares it with the golden
    #   bodies recorded from a live core, so a field can neither vanish from the wire nor appear on
    #   it unnoticed.
    class Model
      class << self
        # Declare a wire field.
        #
        # @param name [Symbol] exactly as the wire spells it
        # @param model [Class, nil] decode into this model
        # @param list [Boolean] the value is an array of `model`
        # @param optional [Boolean] not present on every route that returns this model
        # @return [void]
        def field(name, model: nil, list: false, optional: false, secret: false)
          declared[name] = { model: model, list: list, optional: optional, secret: secret }
          define_method(name) { @attributes[name] }
        end

        # Fields whose value must never print. They stay readable through their own accessor
        # (`endpoint.secret`), and every automatic rendering — {Model#to_h}, {Model#to_json},
        # {Model#inspect} — shows a placeholder instead.
        # @return [Array<Symbol>]
        def secret_keys
          declared.select { |_, spec| spec[:secret] }.keys
        end

        # Declare several plain fields at once.
        # @return [void]
        def fields(*names)
          names.each { |n| field(n) }
        end

        # @return [Hash{Symbol => Hash}] declarations of this class and its ancestors, in order
        def declared
          @declared ||= superclass.respond_to?(:declared) ? superclass.declared.dup : {}
        end

        # The key set the core sends on every route that returns this model. This is what the
        # contract suite compares with the golden bodies.
        # @return [Array<Symbol>]
        def keys
          declared.reject { |_, spec| spec[:optional] }.keys
        end

        # Fields only some routes returning this model carry (`refunds` on payment info, the
        # `claim_token` shown once at creation, …).
        # @return [Array<Symbol>]
        def optional_keys
          declared.select { |_, spec| spec[:optional] }.keys
        end

        # @return [Array<Symbol>] every declared field name, required and optional
        def all_keys
          declared.keys
        end

        # Build from a decoded JSON object.
        # @param value [Hash, nil]
        # @return [self, nil]
        def from(value)
          return nil if value.nil?
          return value if value.is_a?(self)

          new(value)
        end

        # Build from a decoded JSON array.
        # @param value [Array, nil]
        # @return [Array<self>]
        def from_list(value)
          Array(value).map { |item| from(item) }
        end
      end

      # @param attributes [Hash] decoded JSON object, string- or symbol-keyed
      def initialize(attributes = {})
        declared = self.class.declared
        @attributes = {}
        @extra = {}
        attributes.each do |key, value|
          name = key.to_sym
          spec = declared[name]
          if spec.nil?
            @extra[name] = deep_freeze(value)
          else
            @attributes[name] = coerce(value, spec)
          end
        end
        @attributes.freeze
        @extra.freeze
        after_initialize
        freeze
      end

      # Hook for models that precompute a convenience view of their fields. Runs before the object is
      # frozen; must not change the wire attributes.
      # @return [void]
      def after_initialize; end

      # Any field the core sent that this release does not know about, kept verbatim.
      # @return [Hash{Symbol => Object}]
      attr_reader :extra

      # Read a field by name, declared or not.
      # @param name [Symbol, String]
      # @return [Object, nil]
      def [](name)
        key = name.to_sym
        @attributes.key?(key) ? @attributes[key] : @extra[key]
      end

      # @param name [Symbol, String]
      # @return [Boolean] whether the core sent this field
      def key?(name)
        key = name.to_sym
        @attributes.key?(key) || @extra.key?(key)
      end

      # The wire shape: declared fields in declaration order, then anything unknown. Fields declared
      # `secret: true` render as `"[redacted]"` — a serialized model is what ends up in a log line or
      # an audit record, and a one-time secret must not be in either. Read them through their own
      # accessor when you mean to store them.
      # @return [Hash{Symbol => Object}]
      def to_h
        secrets = self.class.secret_keys
        out = {}
        self.class.all_keys.each do |k|
          next unless @attributes.key?(k)

          out[k] = secrets.include?(k) && !@attributes[k].nil? ? REDACTED : unwrap(@attributes[k])
        end
        @extra.each { |k, v| out[k] = v }
        out
      end
      alias to_hash to_h

      # @return [String]
      def to_json(*args)
        require "json"
        to_h.to_json(*args)
      end

      # Compared on the wire values themselves, not on {#to_h}: two endpoints with different secrets
      # are different objects even though both serialize to "[redacted]".
      def ==(other)
        other.class == self.class && other.attributes == attributes && other.extra == extra
      end
      alias eql? ==

      def hash
        [self.class, attributes, extra].hash
      end

      # The decoded wire values, secrets included. This is the raw material; {#to_h} is the
      # printable rendering of it.
      # @return [Hash{Symbol => Object}]
      attr_reader :attributes

      def inspect
        printable = to_h
        shown = printable.first(6).map { |k, v| "#{k}=#{v.inspect}" }.join(" ")
        more = printable.size > 6 ? " ..." : ""
        "#<#{self.class.name} #{shown}#{more}>"
      end

      private

      def coerce(value, spec)
        model = spec[:model]
        return deep_freeze(value) if model.nil? || value.nil?
        return model.from_list(value).freeze if spec[:list]

        model.from(value)
      end

      # A model is a value object: freezing only the top-level hash left every nested array and
      # string it decoded writable, so one holder could mutate another's copy.
      def deep_freeze(value)
        case value
        when Array then value.each { |v| deep_freeze(v) }.freeze
        when Hash
          value.each { |k, v| [k, v].each { |m| deep_freeze(m) } }
          value.freeze
        else value.frozen? ? value : value.freeze
        end
      end

      def unwrap(value)
        case value
        when Model then value.to_h
        when Array then value.map { |v| unwrap(v) }
        else value
        end
      end
    end
  end
end
