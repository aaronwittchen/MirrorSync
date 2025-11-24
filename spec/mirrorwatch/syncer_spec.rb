require 'spec_helper'

RSpec.describe MirrorWatch::Syncer do
  let(:test_upstream) { Dir.mktmpdir('upstream') }
  let(:test_local) { Dir.mktmpdir('local') }
  
  let(:basic_config) do
    {
      'upstream' => "#{test_upstream}/",
      'local_path' => test_local,
      'bwlimit' => '5m'
    }
  end

  let(:include_exclude_config) do
    {
      'upstream' => "#{test_upstream}/",
      'local_path' => test_local,
      'bwlimit' => '5m',
      'include' => ['*.txt', '**/Release'],
      'exclude' => ['*']
    }
  end

  let(:all_mirrors_config) do
    {
      'ubuntu' => basic_config,
      'test-includes' => include_exclude_config
    }
  end

  before do
    # Use the helper to create test mirror structure
    create_test_mirror(test_upstream)
    
    # Mock config loading
    allow(MirrorWatch::Config).to receive(:load).and_return(all_mirrors_config)
  end

  after do
    # Cleanup temporary directories
    FileUtils.rm_rf(test_upstream)
    FileUtils.rm_rf(test_local)
  end

  describe '#initialize' do
    it 'loads the correct config for the mirror' do
      syncer = described_class.new('ubuntu')
      expect(syncer.config).to eq(basic_config)
      expect(syncer.mirror_name).to eq('ubuntu')
    end

    it 'raises an error for unknown mirrors' do
      expect { described_class.new('unknown') }
        .to raise_error(ArgumentError, /Mirror 'unknown' not found in configuration/)
    end

    it 'accepts string or symbol mirror names' do
      syncer_string = described_class.new('ubuntu')
      syncer_symbol = described_class.new(:ubuntu)
      
      expect(syncer_string.mirror_name).to eq('ubuntu')
      expect(syncer_symbol.mirror_name).to eq('ubuntu')
    end
  end

  describe '#sync' do
    context 'basic sync operation' do
      it 'syncs files from upstream to local path' do
        syncer = described_class.new('ubuntu')
        
        expect(syncer.sync).to be true
        
        # Verify files were synced
        expect(File.exist?("#{test_local}/dists/stable/Release")).to be true
        expect(File.exist?("#{test_local}/dists/stable/Packages")).to be true
        expect(File.read("#{test_local}/dists/stable/Release")).to eq("Test Release File\n")
      end

      it 'creates local directory if it does not exist' do
        new_local = File.join(test_local, 'new_subdir')
        basic_config['local_path'] = new_local
        
        syncer = described_class.new('ubuntu')
        syncer.sync
        
        expect(Dir.exist?(new_local)).to be true
      end

      it 'outputs JSON log with sync details' do
        syncer = described_class.new('ubuntu')
        
        output = capture_stdout { syncer.sync }
        
        expect(output).to match(/\[SYNC LOG\]/)
        expect(output).to match(/"mirror":"ubuntu"/)
        expect(output).to match(/"status":"completed"/)
      end

      it 'logs start and completion messages' do
        syncer = described_class.new('ubuntu')
        
        output = capture_stdout { syncer.sync }
        
        expect(output).to match(/Starting sync for ubuntu/)
        expect(output).to match(/Sync completed successfully!/)
      end
    end

    context 'dry-run mode' do
      it 'does not create files in dry-run mode' do
        syncer = described_class.new('ubuntu')
        
        expect(syncer.sync(dry_run: true)).to be true
        
        # Files should NOT exist after dry-run
        expect(File.exist?("#{test_local}/dists/stable/Release")).to be false
      end

      it 'logs dry_run: true in JSON output' do
        syncer = described_class.new('ubuntu')
        
        output = capture_stdout { syncer.sync(dry_run: true) }
        
        expect(output).to match(/"dry_run":true/)
      end
    end

    context 'concurrent sync prevention (locking)' do
      it 'prevents concurrent syncs with lock file' do
        syncer1 = described_class.new('ubuntu')
        syncer2 = described_class.new('ubuntu')
        
        # Use helper to mock slow rsync
        mock_slow_rsync(duration: 0.5)
        
        # Start first sync in background thread
        thread = Thread.new { syncer1.sync }
        sleep 0.1  # Give first sync time to acquire lock
        
        # Second sync should fail with error
        expect { syncer2.sync }.to raise_error(/already in progress/)
        
        thread.join
      end

      it 'cleans up lock file after successful sync' do
        syncer = described_class.new('ubuntu')
        syncer.sync
        
        lock_path = "/tmp/mirrorwatch-ubuntu.lock"
        expect(File.exist?(lock_path)).to be false
      end

      it 'cleans up lock file even if sync fails' do
        syncer = described_class.new('ubuntu')
        
        # Use helper to mock failed rsync
        mock_failed_rsync('rsync error')
        
        syncer.sync
        
        lock_path = "/tmp/mirrorwatch-ubuntu.lock"
        expect(File.exist?(lock_path)).to be false
      end
    end

    context 'include/exclude patterns' do
      it 'respects include patterns' do
        syncer = described_class.new('test-includes')
        syncer.sync
        
        # Should include .txt files
        expect(File.exist?("#{test_local}/test.txt")).to be true
        expect(File.read("#{test_local}/test.txt")).to eq("Include this file\n")
        
        # Should include Release files
        expect(File.exist?("#{test_local}/dists/stable/Release")).to be true
      end

      it 'respects exclude patterns' do
        syncer = described_class.new('test-includes')
        syncer.sync
        
        # Should exclude .log and .md files
        expect(File.exist?("#{test_local}/test.log")).to be false
        expect(File.exist?("#{test_local}/README.md")).to be false
      end
    end

    context 'error handling' do
      it 'handles rsync failures gracefully' do
        syncer = described_class.new('ubuntu')
        
        # Use helper to mock failure
        mock_failed_rsync('connection failed')
        
        expect(syncer.sync).to be false
      end

      it 'logs errors in JSON format' do
        syncer = described_class.new('ubuntu')
        
        mock_failed_rsync('rsync error')
        
        output = capture_stdout { syncer.sync }
        
        expect(output).to match(/"status":"failed"/)
        expect(output).to match(/"exit_status":1/)
      end

      it 'handles exceptions during sync' do
        syncer = described_class.new('ubuntu')
        
        allow(Open3).to receive(:capture3).and_raise(StandardError.new("Network error"))
        
        expect(syncer.sync).to be false
      end
    end
  end

  describe '#build_rsync_command' do
    let(:syncer) { described_class.new('ubuntu') }

    it 'includes basic rsync flags' do
      command = syncer.send(:build_rsync_command)
      
      expect(command).to include('rsync')
      expect(command).to include('-avz')
      expect(command).to include('--delete')
      expect(command).to include('--stats')
      expect(command).to include('--hard-links')
    end

    it 'includes bandwidth limit when configured' do
      command = syncer.send(:build_rsync_command)
      
      expect(command).to include('--bwlimit=5m')
    end

    it 'includes source and destination paths' do
      command = syncer.send(:build_rsync_command)
      
      expect(command).to include("#{test_upstream}/")
      expect(command).to include(test_local)
    end

    it 'includes dry-run flag when requested' do
      command = syncer.send(:build_rsync_command, dry_run: true)
      
      expect(command).to include('--dry-run')
    end

    it 'does not include dry-run by default' do
      command = syncer.send(:build_rsync_command, dry_run: false)
      
      expect(command).not_to include('--dry-run')
    end

    it 'includes include patterns when configured' do
      syncer = described_class.new('test-includes')
      command = syncer.send(:build_rsync_command)
      
      expect(command).to include('--include=*.txt')
      expect(command).to include('--include=**/Release')
    end

    it 'includes exclude patterns when configured' do
      syncer = described_class.new('test-includes')
      command = syncer.send(:build_rsync_command)
      
      expect(command).to include('--exclude=*')
    end

    it 'places include before exclude patterns' do
      syncer = described_class.new('test-includes')
      command = syncer.send(:build_rsync_command)
      
      # Include should come before exclude in the command array
      include_index = command.index { |arg| arg.start_with?('--include') }
      exclude_index = command.index { |arg| arg.start_with?('--exclude') }
      
      expect(include_index).to be < exclude_index
    end
  end

  describe '#parse_rsync_stats' do
    let(:syncer) { described_class.new('ubuntu') }

    it 'parses rsync statistics output' do
      rsync_output = <<~OUTPUT
        Number of files: 1,234
        Number of files transferred: 42
        Total transferred file size: 123.45MB
        Total bytes sent: 1234567
        Total bytes received: 9876543
      OUTPUT

      stats = syncer.send(:parse_rsync_stats, rsync_output)
      
      expect(stats[:files_processed]).to eq(1234)
      expect(stats[:files_transferred]).to eq(42)
      expect(stats[:bytes_transferred]).to eq('123.45MB')
      expect(stats[:bytes_sent]).to eq(1234567)
      expect(stats[:bytes_received]).to eq(9876543)
    end

    it 'returns nil for output without stats' do
      rsync_output = "Some random output without stats"
      
      stats = syncer.send(:parse_rsync_stats, rsync_output)
      
      expect(stats).to be_nil
    end

    it 'handles partial stats gracefully' do
      rsync_output = "Number of files: 100"
      
      stats = syncer.send(:parse_rsync_stats, rsync_output)
      
      expect(stats[:files_processed]).to eq(100)
      expect(stats[:files_transferred]).to be_nil
    end
  end
end