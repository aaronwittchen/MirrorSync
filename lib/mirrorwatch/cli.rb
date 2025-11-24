require 'thor'
require_relative 'logger'

module MirrorWatch
  class CLI < Thor
    def initialize(*args)
      super
      @logger = Logger.new
    end

    desc 'sync', 'Sync mirrors'
    def sync
      @logger.info('Starting sync operation')
      # sync logic
      @logger.info('Sync completed successfully')
    rescue StandardError => e
      @logger.error('Sync failed', error: e.message, backtrace: e.backtrace)
      raise
    end
  end
end
