require 'spec_helper'
require 'tempfile'
require 'pathname'

RSpec.describe MirrorWatch::Config do
  let(:valid_yaml_content) do
    <<~YAML
      ubuntu:
        upstream: 'rsync://example.com/ubuntu/'
        local_path: './mirrors/ubuntu'
        bwlimit: 5000
        schedule: '0 */4 * * *'
    YAML
  end

  let(:invalid_yaml_content) { 'invalid: yaml: syntax' }  # Bad YAML

  let(:invalid_structure_content) do
    <<~YAML
      ubuntu: not_a_hash
    YAML
  end

  let(:missing_key_content) do
    <<~YAML
      ubuntu:
        upstream: 'rsync://example.com/'
        # Missing local_path
    YAML
  end

  describe '.load' do
    context 'when config file exists and is valid' do
      it 'loads and returns the config with absolute paths' do
        Tempfile.create('mirrors.yml') do |file|
          file.write(valid_yaml_content)
          file.rewind

          config = described_class.load(file.path)
          expect(config).to be_a(Hash)
          expect(config['ubuntu']['upstream']).to eq('rsync://example.com/ubuntu/')
          expect(config['ubuntu']['local_path']).to match(%r{/.+/mirrors/ubuntu$})  # Absolute path
        end
      end
    end

    context 'when config file does not exist' do
      it 'falls back to default config and warns' do
        expect { described_class.load('non_existent.yml') }
          .to output(/Configuration file not found/).to_stderr

        config = described_class.load('non_existent.yml')
        expect(config).to eq(described_class::DEFAULT_CONFIG)
      end
    end

    context 'when YAML has syntax errors' do
      it 'warns and falls back to defaults' do
        Tempfile.create('invalid.yml') do |file|
          file.write(invalid_yaml_content)
          file.rewind

          expect { described_class.load(file.path) }
            .to output(/Error parsing YAML/).to_stderr

          config = described_class.load(file.path)
          expect(config).to eq(described_class::DEFAULT_CONFIG)
        end
      end
    end

    context 'when config structure is invalid (not a hash)' do
      it 'raises an error during validation' do
        Tempfile.create('invalid_structure.yml') do |file|
          file.write(invalid_structure_content)
          file.rewind

          expect { described_class.load(file.path) }
            .to raise_error("Invalid configuration for mirror 'ubuntu': expected a Hash")
        end
      end
    end

    context 'when required keys are missing' do
      it 'raises an error during validation' do
        Tempfile.create('missing_key.yml') do |file|
          file.write(missing_key_content)
          file.rewind

          expect { described_class.load(file.path) }
            .to raise_error("Missing required key 'local_path' for mirror 'ubuntu'")
        end
      end
    end

    context 'when other errors occur' do
      it 'warns and falls back to defaults' do
        allow(File).to receive(:exist?).and_raise(StandardError.new('Boom!'))

        expect { described_class.load }
          .to output(/Error loading configuration: Boom!/).to_stderr

        config = described_class.load
        expect(config).to eq(described_class::DEFAULT_CONFIG)
      end
    end
  end
end