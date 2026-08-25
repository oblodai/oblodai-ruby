# frozen_string_literal: true

module Oblodai
  # Amounts are decimal strings; never `to_f` them (USDT has 6 decimals, BTC 8, ETH 18). These
  # helpers compare and add at arbitrary precision, and keep the scale of the widest operand, so
  # `add("10.000000", "0.5")` is `"10.500000"` — the shape the core would have rendered.
  module Money
    DECIMAL = /\A-?\d+(\.\d+)?\z/

    module_function

    # @param amount [String]
    # @return [Boolean] whether the string is a decimal amount the core would accept
    def valid?(amount)
      amount.is_a?(String) && DECIMAL.match?(amount)
    end

    # @param a [String]
    # @param b [String]
    # @return [Integer] -1, 0 or 1
    def compare(a, b)
      scale = scale_of(a, b)
      scaled(a, scale) <=> scaled(b, scale)
    end

    # @return [Boolean]
    def equal?(a, b)
      compare(a, b).zero?
    end

    # @return [String]
    def add(a, b)
      scale = scale_of(a, b)
      unscale(scaled(a, scale) + scaled(b, scale), scale)
    end

    # @return [String]
    def subtract(a, b)
      scale = scale_of(a, b)
      unscale(scaled(a, scale) - scaled(b, scale), scale)
    end

    # @return [Boolean]
    def zero?(amount)
      scaled(amount, scale_of(amount)).zero?
    end

    # @return [Boolean]
    def negative?(amount)
      scaled(amount, scale_of(amount)).negative?
    end

    # @param amount [String]
    # @param scale [Integer]
    # @return [Integer] the amount as an integer number of its smallest units
    def scaled(amount, scale)
      neg, int, frac = parts(amount)
      value = "#{int}#{frac.ljust(scale, "0")}".to_i
      neg ? -value : value
    end

    def parts(amount)
      raise TypeError, "not a decimal amount: #{amount.inspect}" unless valid?(amount)

      neg = amount.start_with?("-")
      int, frac = (neg ? amount[1..] : amount).split(".")
      [neg, int || "0", frac || ""]
    end

    def scale_of(*amounts)
      amounts.map { |a| parts(a)[2].length }.max
    end

    def unscale(value, scale)
      neg = value.negative?
      digits = value.abs.to_s.rjust(scale + 1, "0")
      int = digits[0...(digits.length - scale)]
      frac = digits[(digits.length - scale)..]
      "#{"-" if neg}#{int}#{".#{frac}" unless scale.zero?}"
    end
  end
end
