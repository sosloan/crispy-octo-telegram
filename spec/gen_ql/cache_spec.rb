# frozen_string_literal: true

require 'spec_helper'
require 'gen_ql/cache'

RSpec.describe GenQL::Cache do
  subject(:cache) { described_class.new }

  describe '#write and #read' do
    it 'stores and retrieves a value' do
      cache.write('key', 'value')
      expect(cache.read('key')).to eq 'value'
    end

    it 'returns nil for a missing key' do
      expect(cache.read('missing')).to be_nil
    end

    it 'stores any Ruby object as a value' do
      data = { data: { 'orchards' => [] } }
      cache.write('q', data)
      expect(cache.read('q')).to eq data
    end

    it 'overwrites an existing entry' do
      cache.write('key', 'first')
      cache.write('key', 'second')
      expect(cache.read('key')).to eq 'second'
    end
  end

  describe '#write with TTL' do
    it 'returns a value that has not expired' do
      cache.write('key', 'live', ttl: 60)
      expect(cache.read('key')).to eq 'live'
    end

    it 'returns nil for an expired entry' do
      cache.write('key', 'gone', ttl: 0.01)
      sleep 0.05
      expect(cache.read('key')).to be_nil
    end
  end

  describe '#fetch' do
    it 'calls the block on a cache miss and stores the result' do
      calls = 0
      result = cache.fetch('key') do
        calls += 1
        'computed'
      end
      expect(result).to eq 'computed'
      expect(calls).to eq 1
    end

    it 'does not call the block on a cache hit' do
      cache.write('key', 'cached')
      calls = 0
      result = cache.fetch('key') do
        calls += 1
        'new'
      end
      expect(result).to eq 'cached'
      expect(calls).to eq 0
    end

    it 'calls the block again after TTL expiry' do
      cache.write('key', 'old', ttl: 0.01)
      sleep 0.05
      result = cache.fetch('key', ttl: 60) { 'fresh' }
      expect(result).to eq 'fresh'
    end

    it 'stores the result with the given TTL' do
      cache.fetch('key', ttl: 0.01) { 'temp' }
      sleep 0.05
      expect(cache.read('key')).to be_nil
    end
  end

  describe '#delete' do
    it 'removes an existing entry' do
      cache.write('key', 'value')
      cache.delete('key')
      expect(cache.read('key')).to be_nil
    end

    it 'is a no-op for a missing key' do
      expect { cache.delete('nope') }.not_to raise_error
    end
  end

  describe '#clear' do
    it 'removes all entries' do
      cache.write('a', 1)
      cache.write('b', 2)
      cache.clear
      expect(cache.read('a')).to be_nil
      expect(cache.read('b')).to be_nil
    end

    it 'resets size to zero' do
      cache.write('a', 1)
      cache.clear
      expect(cache.size).to eq 0
    end
  end

  describe '#size' do
    it 'returns 0 for an empty cache' do
      expect(cache.size).to eq 0
    end

    it 'increments with each new entry' do
      cache.write('a', 1)
      cache.write('b', 2)
      expect(cache.size).to eq 2
    end
  end

  describe '#evict_expired' do
    it 'removes expired entries and returns the count' do
      cache.write('live', 'v', ttl: 60)
      cache.write('dead', 'v', ttl: 0.01)
      sleep 0.05
      removed = cache.evict_expired
      expect(removed).to eq 1
      expect(cache.size).to eq 1
      expect(cache.read('live')).to eq 'v'
    end

    it 'returns 0 when nothing has expired' do
      cache.write('a', 1)
      expect(cache.evict_expired).to eq 0
    end
  end

  describe 'thread safety' do
    it 'handles concurrent writes without data loss' do
      10.times.map { |i|
        Thread.new { cache.write("key#{i}", i) }
      }.each(&:join)
      expect(cache.size).to eq 10
    end

    it 'handles concurrent reads safely' do
      cache.write('shared', 'value')
      results = 10.times.map { Thread.new { cache.read('shared') } }.map(&:value)
      expect(results).to all(eq('value'))
    end
  end
end
