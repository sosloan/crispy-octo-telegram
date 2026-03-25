# frozen_string_literal: true

require 'spec_helper'
require 'gen_ql'
require 'saratoga'

CONCURRENT_STRESS_QUERIES = [
  '{ orchards { nodes { name } } }',
  '{ orchards { nodes { id name location established_year } } }',
  '{ orchards { nodes { name varieties { nodes { name season } } } } }',
  '{ varieties { nodes { id name species season notes } } }',
  '{ harvests { nodes { id orchard_id variety_id quantity_kg harvested_at } } }'
].freeze

RSpec.describe 'Stress tests' do
  before { Saratoga::Store.reset! }

  let(:executor) { GenQL::Executor.new(Saratoga::SCHEMA) }

  # ---------------------------------------------------------------------------
  # Lexer stress
  # ---------------------------------------------------------------------------
  describe 'GenQL::Lexer under stress' do
    it 'tokenizes a query containing 500 NAME tokens' do
      fields = Array.new(500) { |i| "field#{i}" }.join(' ')
      source = "{ #{fields} }"
      tokens = GenQL::Lexer.new(source).tokenize
      # LBRACE + 500 NAMEs + RBRACE + EOF
      expect(tokens.map(&:type).count(:NAME)).to eq 500
    end

    it 'tokenizes a query with 100 integer arguments without error' do
      args = Array.new(100) { |i| "arg#{i}: #{i}" }.join(', ')
      source = "{ field(#{args}) { name } }"
      expect { GenQL::Lexer.new(source).tokenize }.not_to raise_error
    end

    it 'tokenizes a 1,000-character string literal correctly' do
      long_value = 'x' * 1_000
      source = "{ field(note: \"#{long_value}\") }"
      tokens = GenQL::Lexer.new(source).tokenize
      string_token = tokens.find { |t| t.type == :STRING }
      expect(string_token.value.length).to eq 1_000
    end

    it 'tokenizes the same query 1,000 times without error' do
      source = '{ orchards { nodes { name location } } }'
      expect { 1_000.times { GenQL::Lexer.new(source).tokenize } }.not_to raise_error
    end

    it 'handles 200 float literals in a single query' do
      args = Array.new(200) { |i| "f#{i}: #{i}.#{i}" }.join(', ')
      source = "{ field(#{args}) }"
      tokens = GenQL::Lexer.new(source).tokenize
      expect(tokens.map(&:type).count(:FLOAT)).to eq 200
    end
  end

  # ---------------------------------------------------------------------------
  # Parser stress
  # ---------------------------------------------------------------------------
  describe 'GenQL::Parser under stress' do
    def parse(source)
      tokens = GenQL::Lexer.new(source).tokenize
      GenQL::Parser.new(tokens).parse
    end

    it 'parses a selection with 100 sibling fields' do
      fields = Array.new(100, 'name').join(' ')
      doc = parse("{ orchards { nodes { #{fields} } } }")
      expect(doc.operations.first.selections.first.selections.first.selections.length).to eq 100
    end

    it 'parses a field with 50 arguments' do
      args = Array.new(50) { |i| "key#{i}: #{i}" }.join(', ')
      doc = parse("{ field(#{args}) { id } }")
      expect(doc.operations.first.selections.first.arguments.length).to eq 50
    end

    it 'parses a 10-level deep nested selection without error' do
      # Builds: { a { b { c { ... { j } ... } } } }
      inner = 'j'
      %w[i h g f e d c b a].each { |n| inner = "#{n} { #{inner} }" }
      expect { parse("{ #{inner} }") }.not_to raise_error
    end

    it 'parses 1,000 documents sequentially without error' do
      source = '{ orchards { nodes { name varieties { nodes { name season } } } } }'
      expect { 1_000.times { parse(source) } }.not_to raise_error
    end

    it 'parses a document containing 20 operations' do
      ops = Array.new(20) { 'query { orchards { nodes { id } } }' }.join(' ')
      doc = parse(ops)
      expect(doc.operations.length).to eq 20
    end

    it 'parses all GenQL value types (string, int, float, true, false, null) in bulk' do
      args = 'str: "hello", num: 42, flt: 3.14, flag: true, off: false, tag: null'
      doc = parse("{ field(#{args}) }")
      parsed_args = doc.operations.first.selections.first.arguments
      expect(parsed_args['str']).to eq 'hello'
      expect(parsed_args['num']).to eq 42
      expect(parsed_args['flt']).to eq 3.14
      expect(parsed_args['flag']).to be true
      expect(parsed_args['off']).to be false
      expect(parsed_args['tag']).to be_nil
    end
  end

  # ---------------------------------------------------------------------------
  # Executor stress
  # ---------------------------------------------------------------------------
  describe 'GenQL::Executor under stress' do
    it 'executes 500 iterations of a simple query without error' do
      query = '{ orchards { nodes { name } } }'
      expect { 500.times { executor.execute(query) } }.not_to raise_error
    end

    it 'resolves all root fields in a single fully-expanded query' do
      query = <<~GQL
        {
          orchards {
            nodes {
              id name location established_year
              varieties { nodes { id name species season notes } }
              harvests  { nodes { id quantity_kg harvested_at } }
            }
          }
          varieties { nodes { id name species season notes } }
          harvests  { nodes { id orchard_id variety_id quantity_kg harvested_at notes
                              variety { name season } } }
        }
      GQL
      result = executor.execute(query)
      expect(result[:data]['orchards']['nodes']).to  be_an(Array)
      expect(result[:data]['varieties']['nodes']).to be_an(Array)
      expect(result[:data]['harvests']['nodes']).to  be_an(Array)
      expect(result[:errors]).to be_nil
    end

    it 'executes 200 addHarvest mutations and persists all of them' do
      200.times do |i|
        query = 'mutation { addHarvest(orchard_id: "o1", variety_id: "v1", ' \
                "quantity_kg: #{100 + i}, harvested_at: \"2024-01-01\") { id quantity_kg } }"
        result = executor.execute(query)
        expect(result[:errors]).to be_nil
      end
      result = executor.execute('{ harvests { page_info { total_count } } }')
      expect(result[:data]['harvests']['page_info']['total_count']).to eq(4 + 200)
    end

    it 'accumulates no errors across 200 successful read queries' do
      query = '{ orchards { nodes { name location varieties { nodes { name } } harvests { nodes { id } } } } }'
      errors_seen = []
      200.times do
        result = executor.execute(query)
        errors_seen << result[:errors] if result[:errors]
      end
      expect(errors_seen).to be_empty
    end

    it 'reports errors for every unknown-field query across 100 iterations' do
      query = '{ nonexistent_field }'
      100.times do
        result = executor.execute(query)
        expect(result[:errors]).not_to be_empty
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Store stress
  # ---------------------------------------------------------------------------
  describe 'Saratoga::Store under stress' do
    it 'adds 1,000 harvests and maintains the correct total count' do
      1_000.times do |i|
        Saratoga::Store.add_harvest(
          orchard_id: "o#{(i % 3) + 1}",
          variety_id: "v#{(i % 5) + 1}",
          quantity_kg: 100 + i,
          harvested_at: '2024-06-01'
        )
      end
      expect(Saratoga::Store.harvests.length).to eq 1_004
    end

    it 'assigns a unique id to every harvest added in bulk' do
      500.times do |i|
        Saratoga::Store.add_harvest(
          orchard_id: 'o1',
          variety_id: 'v1',
          quantity_kg: i + 1,
          harvested_at: '2024-06-01'
        )
      end
      ids = Saratoga::Store.harvests.map(&:id)
      expect(ids.uniq.length).to eq ids.length
    end

    it 'resets cleanly after a bulk load and restores seed counts' do
      300.times do |i|
        Saratoga::Store.add_harvest(
          orchard_id: 'o2',
          variety_id: 'v2',
          quantity_kg: i + 50,
          harvested_at: '2024-07-01'
        )
      end
      Saratoga::Store.reset!
      expect(Saratoga::Store.harvests.length).to  eq 4
      expect(Saratoga::Store.orchards.length).to  eq 3
      expect(Saratoga::Store.varieties.length).to eq 5
    end

    it 'returns correct variety objects after 500 harvests are added' do
      500.times do |i|
        Saratoga::Store.add_harvest(
          orchard_id: 'o1',
          variety_id: 'v1',
          quantity_kg: 10 + i,
          harvested_at: '2024-06-01'
        )
      end
      harvest = Saratoga::Store.harvests.last
      expect(harvest.variety.name).to eq 'Gravenstein'
    end
  end

  # ---------------------------------------------------------------------------
  # Concurrent-user stress — 2,001 simultaneous threads
  # ---------------------------------------------------------------------------
  describe '2,001 concurrent users' do
    # Spawn +count+ threads, hold them at a barrier, release all at once, then
    # join all threads.  The caller-supplied block receives the thread index.
    def run_concurrent_barrier(count, &block)
      barrier_mx = Mutex.new
      barrier_cv = ConditionVariable.new
      ready      = [0]
      go         = [false]
      threads = count.times.map do |i|
        Thread.new do
          barrier_mx.synchronize do
            ready[0] += 1
            barrier_cv.wait(barrier_mx) until go[0]
          end
          block.call(i)
        end
      end
      sleep 0.001 until barrier_mx.synchronize { ready[0] == count }
      barrier_mx.synchronize do
        go[0] = true
        barrier_cv.broadcast
      end
      threads.each(&:join)
    end

    it 'executes 2,001 simultaneous read queries without errors or data races' do
      errors = []
      err_mx = Mutex.new
      run_concurrent_barrier(2_001) do |i|
        result = executor.execute(CONCURRENT_STRESS_QUERIES[i % CONCURRENT_STRESS_QUERIES.length])
        err_mx.synchronize { errors << result[:errors] } if result[:errors]
      end
      expect(errors).to be_empty
    end

    it 'returns consistent orchard data across 2,001 concurrent readers' do
      results = Array.new(2_001)
      run_concurrent_barrier(2_001) do |i|
        results[i] = executor.execute('{ orchards { nodes { id name } } }')
      end
      first = results.first[:data]['orchards']['nodes']
      expect(results.all? { |r| r[:data]['orchards']['nodes'] == first }).to be true
    end
  end

  # ---------------------------------------------------------------------------
  # Schema integration stress
  # ---------------------------------------------------------------------------
  describe 'Saratoga schema integration under stress' do
    it 'queries a large harvest list after 100 mutations via the executor' do
      100.times do |i|
        executor.execute(
          "mutation { addHarvest(orchard_id: \"o1\", variety_id: \"v#{(i % 5) + 1}\", " \
          "quantity_kg: #{200 + i}, harvested_at: \"2024-09-01\") { id } }"
        )
      end
      result = executor.execute('{ harvests { nodes { id orchard_id variety_id quantity_kg } } }')
      expect(result[:data]['harvests']['nodes'].length).to eq 104
      expect(result[:errors]).to be_nil
    end

    it 'resolves orchard→varieties→harvests for all orchards after 50 bulk adds' do
      50.times do |i|
        Saratoga::Store.add_harvest(
          orchard_id: "o#{(i % 3) + 1}",
          variety_id: "v#{(i % 5) + 1}",
          quantity_kg: 50 + i,
          harvested_at: '2024-08-15'
        )
      end
      result = executor.execute(
        '{ orchards { nodes { id name varieties { nodes { name } } harvests { nodes { id quantity_kg } } } } }'
      )
      orchards = result[:data]['orchards']['nodes']
      expect(orchards.length).to eq 3
      expect(orchards.all? { |o| o['harvests']['nodes'].is_a?(Array) }).to be true
    end

    it 'returns identical data for 50 repeated identical queries' do
      query = '{ orchards { nodes { id name } } varieties { nodes { id name } } harvests { nodes { id } } }'
      first_result = executor.execute(query)
      50.times do
        result = executor.execute(query)
        expect(result[:data]).to eq first_result[:data]
      end
    end

    it 'handles alternating queries and mutations for 100 cycles without error' do
      100.times do |i|
        mut = 'mutation { addHarvest(orchard_id: "o1", variety_id: "v1", ' \
              "quantity_kg: #{i + 1}, harvested_at: \"2024-10-01\") { id } }"
        mut_result = executor.execute(mut)
        expect(mut_result[:errors]).to be_nil

        qry_result = executor.execute('{ harvests { nodes { id } } }')
        expect(qry_result[:errors]).to be_nil
      end
    end
  end
end
