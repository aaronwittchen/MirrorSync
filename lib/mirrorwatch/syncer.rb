require 'open3'
require 'json'
require 'time'
require 'fileutils'

module MirrorWatch
  class Syncer
    attr_reader :mirror_name, :config

    def initialize(mirror_name)
      @mirror_name = mirror_name.to_s
      config_data = Config.load
      
      # Try both string and symbol keys
      @config = config_data[@mirror_name] || config_data[mirror_name.to_sym]
      @lock_path = "/tmp/mirrorwatch-#{@mirror_name}.lock"
      
      unless @config
        raise ArgumentError, "Mirror '#{@mirror_name}' not found in configuration"
      end
    end

    def sync(dry_run: false)
      acquire_lock do
        perform_sync(dry_run: dry_run)
      end
    end

    private

    def perform_sync(dry_run: false)
      start_time = Time.now
      log_entry = {
        timestamp: start_time.iso8601,
        mirror: mirror_name,
        command: nil,
        dry_run: dry_run,
        status: 'started',
        stdout: '',
        stderr: '',
        exit_status: nil,
        duration_seconds: nil,
        files_transferred: 0,
        bytes_transferred: 0
      }

      begin
        rsync_cmd = build_rsync_command(dry_run: dry_run)

        log_entry[:command] = rsync_cmd.join(' ')
        puts "[#{log_entry[:timestamp]}] Starting sync for #{mirror_name}"
        puts "  Command: #{log_entry[:command]}"
        
        FileUtils.mkdir_p(config['local_path'])
        
        stdout, stderr, status = Open3.capture3(*rsync_cmd)
        
        log_entry[:stdout] = stdout
        log_entry[:stderr] = stderr
        log_entry[:exit_status] = status.exitstatus
        log_entry[:status] = status.success? ? 'completed' : 'failed'
        
        if status.success? && stdout.include?('Number of files:')
          stats = parse_rsync_stats(stdout)
          log_entry.merge!(stats) if stats
        end
        
        puts stdout unless stdout.empty?
        $stderr.puts stderr unless stderr.empty?
        
        if status.success?
          puts "[#{Time.now.iso8601}] Sync completed successfully!"
        else
          $stderr.puts "[#{Time.now.iso8601}] Sync failed with status: #{status.exitstatus}"
        end
        
        status.success?
      rescue => e
        log_entry[:status] = 'error'
        log_entry[:stderr] = "#{e.class}: #{e.message}\n#{e.backtrace.join("\n")}"
        $stderr.puts "[#{Time.now.iso8601}] Error during sync: #{e.message}"
        false
      ensure
        end_time = Time.now
        log_entry[:duration_seconds] = (end_time - start_time).round(2)
        
        log_json = log_entry.to_json
        puts "\n[SYNC LOG] #{log_json}"
        
        # Optionally write to log file
        # File.open('mirrorwatch.log', 'a') { |f| f.puts(log_json) }
      end
    end

    def build_rsync_command(dry_run: false)
      cmd = [
        'rsync',
        '-avz',
        '--delete',
        '--stats',
        '--human-readable',
        '--hard-links'
      ]

      if config['bwlimit']
        cmd << "--bwlimit=#{config['bwlimit']}"
      end
      if config['include']
        included_dirs = config['include'].flat_map do |pattern|
          pattern.split('/')[0..-2].inject([]) do |dirs, dir|
            dirs << (dirs.last ? File.join(dirs.last, dir) : dir)
          end
        end.uniq

        included_dirs.each do |dir|
          cmd << "--include=#{dir}/"
        end
        config['include'].each do |pattern|
          cmd << "--include=#{pattern}"
        end

        cmd << '--exclude=*'
      end

      if config['exclude'] && !config['include']
        config['exclude'].each do |pattern|
          cmd << "--exclude=#{pattern}"
        end
      end

      cmd << '--dry-run' if dry_run

      cmd << config['upstream']
      cmd << config['local_path']

      cmd
    end

    def acquire_lock
      File.open(@lock_path, File::CREAT | File::WRONLY) do |f|
        unless f.flock(File::LOCK_EX | File::LOCK_NB)
          error_msg = "Another sync is running for #{mirror_name}"
          $stderr.puts "[#{Time.now.iso8601}] ERROR: #{error_msg}"
          raise "Sync already in progress for #{mirror_name}"
        end

        begin
          yield
        ensure
          f.flock(File::LOCK_UN)
          File.delete(@lock_path) if File.exist?(@lock_path)
        end
      end
    rescue Errno::ENOENT => e
      $stderr.puts "[#{Time.now.iso8601}] Failed to create lock file: #{e.message}"
      raise
    end
    
    def parse_rsync_stats(output)
      stats = {}
      
      if match = output.match(/Number of files: ([\d,]+)/)
        stats[:files_processed] = match[1].gsub(',', '').to_i
      end
      
      if match = output.match(/Number of files transferred: ([\d,]+)/)
        stats[:files_transferred] = match[1].gsub(',', '').to_i
      end
      
      if match = output.match(/Total transferred file size: ([\d\.,]+[KMG]?B)/)
        stats[:bytes_transferred] = match[1]
      end
      
      if match = output.match(/Total bytes sent: ([\d,]+)/)
        stats[:bytes_sent] = match[1].gsub(',', '').to_i
      end
      
      if match = output.match(/Total bytes received: ([\d,]+)/)
        stats[:bytes_received] = match[1].gsub(',', '').to_i
      end
      
      stats.empty? ? nil : stats
    end
  end
end