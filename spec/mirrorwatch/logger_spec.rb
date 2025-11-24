require 'spec_helper'
require 'timecop'

RSpec.describe MirrorWatch::Logger do
  let(:output) { StringIO.new }
  let(:logger) { described_class.new(output) }

  describe '#info' do
    it 'logs a message with info level' do
      Timecop.freeze(Time.utc(2025, 1, 1, 12, 0, 0)) do
        logger.info('Test message', key: 'value')
      end

      log = JSON.parse(output.string, symbolize_names: true)
      expect(log).to include(
        timestamp: '2025-01-01T12:00:00Z',
        level: 'info',
        message: 'Test message',
        key: 'value'
      )
    end
  end

  describe 'log levels' do
    %i[debug info warn error fatal].each do |level|
      it "responds to #{level}" do
        expect(logger).to respond_to(level)
      end
    end
  end
end
