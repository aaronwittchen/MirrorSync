require 'yaml'
require 'pathname'

module MirrorWatch
  class Config
    DEFAULT_CONFIG = {
      'ubuntu' => {
        'upstream' => 'rsync://rsync.releases.ubuntu.com/releases/',
        'local_path' => './mirrors/ubuntu',
        'bwlimit' => 10000,
        'schedule' => '0 3,15 * * *'
      }
    }.freeze

    def self.load(config_path = nil)
      config_path ||= File.expand_path('../../../config/mirrors.yml', __dir__)

      yaml_content = begin
        if File.exist?(config_path)
          YAML.load_file(config_path)
        else
          warn "Configuration file not found at #{config_path}, using default configuration"
          return DEFAULT_CONFIG
        end
      rescue Psych::SyntaxError => e
        warn "Error parsing YAML configuration: #{e.message}"
        return DEFAULT_CONFIG
      rescue StandardError => e
        warn "Error loading configuration: #{e.message}"
        return DEFAULT_CONFIG
      end

      validate_config(yaml_content, config_path)
      yaml_content
    end

    private

    def self.validate_config(config, config_path)
      raise 'Configuration must be a Hash' unless config.is_a?(Hash)

      config.each do |mirror_name, mirror_config|
        unless mirror_config.is_a?(Hash)
          raise "Invalid configuration for mirror '#{mirror_name}': expected a Hash"
        end

        %w[upstream local_path].each do |required_key|
          unless mirror_config.key?(required_key)
            raise "Missing required key '#{required_key}' for mirror '#{mirror_name}'"
          end
        end

        # Convert relative paths to absolute
        if mirror_config['local_path']
          mirror_config['local_path'] = File.expand_path(
            mirror_config['local_path'],
            File.dirname(config_path)
          )
        end
      end
    end
  end
end