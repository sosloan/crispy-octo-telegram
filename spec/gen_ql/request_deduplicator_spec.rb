# frozen_string_literal: true

require 'spec_helper'
require 'gen_ql'

RSpec.describe GenQL::RequestDeduplicator do
  subject(:dedup) { described_class.new(ttl: 2) }

  # ---------------------------------------------------------------------------
  # Basic behaviour
  # ---------------------------------------------------------------------------
  describe '#execute' do
    it 'returns the block result for a fresh key' do
      result = dedup.execute(:key) { 42 }
      expect(result).to eq 42
    end

    it 'calls the block exactly once when executed twice with the same key within the TTL' do
      call_count = 0
      2.times do
        dedup.execute(:key) do
          call_count += 1
          'value'
        end
      end
      expect(call_count).to eq 1
    end

    it 'calls the block again after the TTL expires' do
      call_count = 0
      dedup_short = described_class.new(ttl: 0)
      2.times do
        dedup_short.execute(:key) do
          call_count += 1
          'value'
        end
      end
      expect(call_count).to eq 2
    end

    it 'treats different keys independently' do
      r1 = dedup.execute(:a) { 1 }
      r2 = dedup.execute(:b) { 2 }
      expect(r1).to eq 1
      expect(r2).to eq 2
    end

    it 'propagates exceptions raised inside the block' do
      expect { dedup.execute(:err_key) { raise 'boom' } }.to raise_error(RuntimeError, 'boom')
    end

    it 'does not cache a result when the block raises' do
      call_count = 0
      dedup_fault = described_class.new(ttl: 60)
      begin
        dedup_fault.execute(:key) do
          call_count += 1
          raise 'oops'
        end
      rescue RuntimeError
        nil
      end
      begin
        dedup_fault.execute(:key) do
          call_count += 1
          raise 'oops'
        end
      rescue RuntimeError
        nil
      end
      expect(call_count).to eq 2
    end
  end

  # ---------------------------------------------------------------------------
  # clear!
  # ---------------------------------------------------------------------------
  describe '#clear!' do
    it 'forces the next call to re-execute the block after clearing' do
      call_count = 0
      dedup.execute(:key) do
        call_count += 1
        'v'
      end
      dedup.clear!
      dedup.execute(:key) do
        call_count += 1
        'v'
      end
      expect(call_count).to eq 2
    end
  end

  # ---------------------------------------------------------------------------
  # Concurrency — identical in-flight requests are coalesced
  # ---------------------------------------------------------------------------
  describe 'concurrent deduplication' do
    def run_concurrent(count)
      barrier_mx = Mutex.new
      barrier_cv = ConditionVariable.new
      ready      = [0]
      go         = [false]

      threads = count.times.map do |i|
        Thread.new(i) do |idx|
          barrier_mx.synchronize do
            ready[0] += 1
            barrier_cv.wait(barrier_mx) until go[0]
          end
          yield idx
        end
      end

      sleep 0.001 until barrier_mx.synchronize { ready[0] == count }
      barrier_mx.synchronize do
        go[0] = true
        barrier_cv.broadcast
      end
      threads.map(&:value)
    end

    it 'executes the block only once when 50 threads call with the same key simultaneously' do
      call_count_mx = Mutex.new
      call_count    = 0

      results = run_concurrent(50) do
        dedup.execute(:shared) do
          call_count_mx.synchronize { call_count += 1 }
          sleep 0.01
          'shared_result'
        end
      end

      expect(call_count).to eq 1
      expect(results).to all eq 'shared_result'
    end

    it 'returns no errors for 100 concurrent callers with two different keys' do
      errors = []
      err_mx = Mutex.new

      run_concurrent(100) do |i|
        key = i.even? ? :even : :odd
        dedup.execute(key) { "result_#{key}" }
      rescue StandardError => e
        err_mx.synchronize { errors << e }
      end

      expect(errors).to be_empty
    end

    it 'propagates the block error to all waiting threads when the executor raises' do
      dedup_no_cache = described_class.new(ttl: 0)
      barrier_mx = Mutex.new
      barrier_cv = ConditionVariable.new
      ready      = [0]
      go         = [false]

      threads = 20.times.map do
        Thread.new do
          barrier_mx.synchronize do
            ready[0] += 1
            barrier_cv.wait(barrier_mx) until go[0]
          end
          dedup_no_cache.execute(:boom_key) do
            sleep 0.01
            raise 'block_error'
          end
        end
      end

      sleep 0.001 until barrier_mx.synchronize { ready[0] == 20 }
      barrier_mx.synchronize do
        go[0] = true
        barrier_cv.broadcast
      end

      results = threads.map do |t|
        t.join
        :ok
      rescue RuntimeError
        :error
      end
      expect(results).to all eq :error
    end
  end
end

# ---------------------------------------------------------------------------
# Executor integration
# ---------------------------------------------------------------------------
RSpec.describe GenQL::Executor, 'with request deduplication' do
  let(:call_log) { [] }
  let(:log_mx)   { Mutex.new }

  let(:query_type) do
    log = call_log
    mx  = log_mx

    GenQL::ObjectType.new('Query') do
      field(:ping, GenQL::StringType) do
        mx.synchronize { log << :ping }
        'pong'
      end
    end
  end

  let(:mutation_type) do
    log = call_log
    mx  = log_mx

    GenQL::ObjectType.new('Mutation') do
      field(:touch, GenQL::StringType) do
        mx.synchronize { log << :touch }
        'touched'
      end
    end
  end

  let(:schema) { GenQL::Schema.new(query: query_type, mutation: mutation_type) }
  subject(:exec) { described_class.new(schema) }

  it 'deduplicates repeated identical query calls within TTL' do
    2.times { exec.execute('{ ping }') }
    expect(call_log.count(:ping)).to eq 1
  end

  it 'does NOT deduplicate mutation operations' do
    2.times { exec.execute('mutation { touch }') }
    expect(call_log.count(:touch)).to eq 2
  end

  it 'treats different query strings as distinct cache entries' do
    exec.execute('{ ping }')
    exec.execute('query { ping }')
    # Both reach the resolver because the strings differ
    expect(call_log.count(:ping)).to eq 2
  end
end
