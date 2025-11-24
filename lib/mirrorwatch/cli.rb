require 'thor'
require_relative 'logger'

module MirrorWatch
  class CLI < Thor
    def initialize(*args)
      super
      @logger = Logger.new
    end

    desc 'sync MIRROR', 'Sync the specified mirror'
    option :mirror, type: :string, aliases: '-m', required: true,
                    desc: 'Name of the mirror to sync (e.g., ubuntu)'
    def sync
      @logger.info("Starting sync for mirror: #{options[:mirror]}")
      
      begin
        syncer = Syncer.new(options[:mirror])
        syncer.sync
        @logger.info('Sync completed successfully')
      rescue StandardError => e
        @logger.error('Sync failed', error: e.message, backtrace: e.backtrace)
        raise
      end
    end
    
    def self.exit_on_failure?
      true
    end
  end
end
