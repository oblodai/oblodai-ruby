# frozen_string_literal: true

require "uri"

module Oblodai
  # Minimal structured-logger contract: anything responding to debug/info/warn/error(message,
  # fields) fits (a Ruby ::Logger wrapper, a Rails logger, semantic_logger). Field values that
  # carry secrets are redacted before they reach the logger, so a debug log never leaks a key,
  # a signature or a cheque passcode.
  module Logging
    # `device_code` is the CLI device flow's polling secret; `api-key` covers `X-Api-Key` and `api_key`.
    SENSITIVE = /secret|signature|passcode|token|authorization|password|claim_url|device_code|api[-_]?key|cookie/i
    # Path and query parameters that carry a bearer secret: the claim token of `/v1/claim/{token}` and
    # `/v1/aml/{token}`, a signed link's `sig`/`exp` (plus every name {SENSITIVE} flags).
    SENSITIVE_PARAM = /\A(?:sig|exp|code)\z|_code\z|passcode/i
    # What a secret value is shown as.
    REDACTED = "[redacted]"

    module_function

    # Whether a path or query parameter of this name carries a secret (masked in every URL the SDK
    # shows: hook `RequestInfo#url`, error messages).
    # @return [Boolean]
    def sensitive_param?(name)
      SENSITIVE.match?(name.to_s) || SENSITIVE_PARAM.match?(name.to_s)
    end

    # A URL a server pointed at (a redirect `Location`), reduced to its scheme and host: its path and
    # query may carry the very token or signature the request did.
    # @return [String, nil]
    def redact_location(url)
      return url if url.nil? || url.to_s.empty?

      uri = URI.parse(url.to_s)
      return REDACTED if uri.scheme.nil? || uri.host.nil?

      port = uri.port && uri.port != uri.default_port ? ":#{uri.port}" : ""
      "#{uri.scheme}://#{uri.host}#{port}/#{REDACTED}"
    rescue URI::InvalidURIError
      REDACTED
    end

    # Replace values of sensitive-looking keys, recursively, without touching the original object.
    # @param value [Object]
    # @return [Object]
    def redact(value)
      case value
      when Array then value.map { |v| redact(v) }
      when Hash
        value.each_with_object({}) do |(k, v), out|
          out[k] = SENSITIVE.match?(k.to_s) ? "[redacted]" : redact(v)
        end
      else value
      end
    end

    # Wrap a logger so its fields are redacted before it sees them. The SDK does this once, around
    # the logger the caller supplied: redaction that lived inside {Oblodai::IOLogger} alone would
    # protect only the SDK's own logger and quietly leave a Rails or semantic_logger user exposed.
    # @param logger [#debug]
    # @return [Oblodai::Logging::Redacting]
    def redacting(logger)
      logger.is_a?(Redacting) || logger.is_a?(NullLogger) ? logger : Redacting.new(logger)
    end
  end

  # A logger façade that scrubs every field before passing it on. See {Logging.redacting}.
  class Logging::Redacting
    # @param inner [#debug]
    def initialize(inner)
      @inner = inner
    end

    %i[debug info warn error].each do |level|
      define_method(level) do |message, fields = nil|
        @inner.public_send(level, message, fields && Logging.redact(fields))
      end
    end
  end

  # Discards everything. The default when no logger is configured.
  class NullLogger
    def debug(_message, _fields = nil); end
    def info(_message, _fields = nil); end
    def warn(_message, _fields = nil); end
    def error(_message, _fields = nil); end
  end

  # Writes one line per event to an IO, gated by level. `OBLODAI_LOG=debug|info|warn|error`
  # selects it from the environment when no logger is passed.
  class IOLogger
    LEVELS = { debug: 0, info: 1, warn: 2, error: 3 }.freeze

    # @param level [Symbol]
    # @param io [IO]
    def initialize(level = :warn, io = $stderr)
      @min = LEVELS.fetch(level.to_sym, 2)
      @io = io
    end

    LEVELS.each_key do |level|
      define_method(level) do |message, fields = nil|
        emit(level, message, fields)
      end
    end

    private

    def emit(level, message, fields)
      return if LEVELS[level] < @min

      line = "[oblodai] #{level.to_s.upcase} #{message}"
      line += " #{Logging.redact(fields).inspect}" if fields && !fields.empty?
      @io.puts(line)
    end
  end
end
