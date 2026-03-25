# frozen_string_literal: true

require 'spec_helper'
require 'gen_ql/subscription_broker'

RSpec.describe GenQL::SubscriptionBroker do
  before { described_class.reset! }
  after  { described_class.reset! }

  describe '.subscribe' do
    it 'returns an opaque subscription id' do
      id = described_class.subscribe('myEvent') { |_d| }
      expect(id).to be_a(String)
      expect(id).not_to be_empty
    end
  end

  describe '.publish' do
    it 'calls registered callbacks with the event data' do
      received = []
      described_class.subscribe('harvest') { |d| received << d }
      described_class.publish('harvest', { id: 'h1' })
      expect(received).to eq [{ id: 'h1' }]
    end

    it 'calls multiple subscribers for the same event' do
      results = []
      described_class.subscribe('evt') { |d| results << "a:#{d}" }
      described_class.subscribe('evt') { |d| results << "b:#{d}" }
      described_class.publish('evt', 'hello')
      expect(results).to contain_exactly('a:hello', 'b:hello')
    end

    it 'does not call subscribers for other events' do
      received = []
      described_class.subscribe('eventA') { |d| received << d }
      described_class.publish('eventB', 'data')
      expect(received).to be_empty
    end
  end

  describe '.unsubscribe' do
    it 'stops the callback from being called after unsubscription' do
      received = []
      id = described_class.subscribe('evt') { |d| received << d }
      described_class.unsubscribe(id)
      described_class.publish('evt', 'data')
      expect(received).to be_empty
    end

    it 'is a no-op for unknown ids' do
      expect { described_class.unsubscribe('nonexistent-id') }.not_to raise_error
    end
  end

  describe '.reset!' do
    it 'clears all subscribers so no callbacks are fired after reset' do
      received = []
      described_class.subscribe('evt') { |d| received << d }
      described_class.reset!
      described_class.publish('evt', 'data')
      expect(received).to be_empty
    end
  end

  describe '.subscribe to multiple events' do
    it 'a single subscriber can listen to multiple distinct events' do
      received = []
      described_class.subscribe('evt1') { |d| received << "1:#{d}" }
      described_class.subscribe('evt2') { |d| received << "2:#{d}" }
      described_class.publish('evt1', 'x')
      described_class.publish('evt2', 'y')
      expect(received).to contain_exactly('1:x', '2:y')
    end

    it 'publishes nil data without error' do
      received = []
      described_class.subscribe('nil_evt') { |d| received << d }
      described_class.publish('nil_evt', nil)
      expect(received).to eq [nil]
    end

    it 'does nothing when publishing to an event with no subscribers' do
      expect { described_class.publish('phantom', 'data') }.not_to raise_error
    end
  end
end
