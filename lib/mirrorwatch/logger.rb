require 'json'
require 'time'

module MirrorWatch
  class Logger
    LEVELS = %i[debug info warn error fatal].freeze

    def initialize(output = $stdout)
      @output = output
    end

    LEVELS.each do |level|
      define_method(level) do |message = nil, **extra|
        log(level, message, **extra)
      end
    end

    private

    def log(level, message = nil, **extra)
      log_data = {
        timestamp: Time.now.utc.iso8601,
        level: level.to_s,
        message: (message || '').to_s
      }.merge(extra)

      @output.puts(log_data.to_json)
      @output.flush
    end
  end
end
