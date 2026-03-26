# frozen_string_literal: true

require 'spec_helper'
require 'gen_ql'

RSpec.describe GenQL::Executor do
  # Build a small in-memory schema for isolated executor tests
  let(:person_type) do
    GenQL::ObjectType.new('Person') do
      field(:name, GenQL::StringType)
      field(:age,  GenQL::IntType)
    end
  end

  let(:query_type) do
    people_data = [
      { 'name' => 'Alice', 'age' => 31 },
      { 'name' => 'Bob',   'age' => 25 }
    ]

    outer_person_type = person_type

    GenQL::ObjectType.new('Query') do
      field(:people, outer_person_type) { |_p, _a, _c| people_data }
      field(:person, outer_person_type) { |_p, args, _c| people_data.find { |p| p['name'] == args['name'] } }
      field(:greeting, GenQL::StringType) { |_p, _a, _c| 'Hello from Saratoga' }
    end
  end

  let(:mutation_type) do
    GenQL::ObjectType.new('Mutation') do
      field(:echo, GenQL::StringType) { |_p, args, _c| args['value'] }
    end
  end

  let(:schema)   { GenQL::Schema.new(query: query_type, mutation: mutation_type) }
  subject(:exec) { described_class.new(schema) }

  describe '#subscribe' do
    let(:subscription_type) do
      outer_person_type = person_type
      GenQL::ObjectType.new('Subscription') do
        field(:personAdded, outer_person_type, description: 'Fires when a person is added')
      end
    end

    let(:schema_with_sub) do
      GenQL::Schema.new(query: query_type, mutation: mutation_type, subscription: subscription_type)
    end
    subject(:exec_with_sub) { described_class.new(schema_with_sub) }

    before { GenQL::SubscriptionBroker.reset! }
    after  { GenQL::SubscriptionBroker.reset! }

    it 'returns an array of subscription IDs' do
      ids = exec_with_sub.subscribe('subscription { personAdded { name } }') { |_r| }
      expect(ids).to be_an(Array)
      expect(ids.length).to eq 1
    end

    it 'delivers resolved payloads when the event is published' do
      payloads = []
      exec_with_sub.subscribe('subscription { personAdded { name age } }') { |r| payloads << r }

      GenQL::SubscriptionBroker.publish('personAdded', { 'name' => 'Carol', 'age' => 28 })

      expect(payloads.length).to eq 1
      expect(payloads.first[:data]['personAdded']).to eq({ 'name' => 'Carol', 'age' => 28 })
    end

    it 'stops delivering after unsubscribing' do
      payloads = []
      ids = exec_with_sub.subscribe('subscription { personAdded { name } }') { |r| payloads << r }
      ids.each { |id| GenQL::SubscriptionBroker.unsubscribe(id) }

      GenQL::SubscriptionBroker.publish('personAdded', { 'name' => 'Dave', 'age' => 40 })
      expect(payloads).to be_empty
    end

    it 'raises ExecutionError when no subscription type is defined in the schema' do
      expect do
        exec.subscribe('subscription { personAdded { name } }') { |_r| }
      end.to raise_error(GenQL::ExecutionError, /No subscription type/)
    end

    it 'raises ExecutionError for unknown subscription fields' do
      expect do
        exec_with_sub.subscribe('subscription { unknownField { name } }') { |_r| }
      end.to raise_error(GenQL::ExecutionError, /unknownField/)
    end
  end

  describe '#execute' do
    it 'resolves a simple scalar field' do
      result = exec.execute('{ greeting }')
      expect(result[:data]['greeting']).to eq 'Hello from Saratoga'
    end

    it 'resolves a list of objects with sub-selections' do
      result = exec.execute('{ people { name age } }')
      people = result[:data]['people']
      expect(people).to eq [
        { 'name' => 'Alice', 'age' => 31 },
        { 'name' => 'Bob',   'age' => 25 }
      ]
    end

    it 'resolves a single object via argument' do
      result = exec.execute('{ person(name: "Alice") { name age } }')
      expect(result[:data]['person']).to eq({ 'name' => 'Alice', 'age' => 31 })
    end

    it 'returns nil for a not-found single object' do
      result = exec.execute('{ person(name: "Nobody") { name } }')
      expect(result[:data]['person']).to be_nil
    end

    it 'returns data without an errors key on success' do
      result = exec.execute('{ greeting }')
      expect(result).not_to have_key(:errors)
    end

    it 'executes a mutation' do
      result = exec.execute('mutation { echo(value: "ping") }')
      expect(result[:data]['echo']).to eq 'ping'
    end

    it 'collects errors for unknown fields' do
      result = exec.execute('{ nonexistent }')
      expect(result[:errors]).not_to be_empty
      expect(result[:errors].first[:message]).to include('nonexistent')
    end

    it 'includes errors key only when there are errors' do
      good_result = exec.execute('{ greeting }')
      bad_result  = exec.execute('{ no_such_field }')
      expect(good_result).not_to have_key(:errors)
      expect(bad_result).to have_key(:errors)
    end

    it 'raises ExecutionError for undefined mutation type' do
      no_mutation_schema = GenQL::Schema.new(query: query_type)
      executor = described_class.new(no_mutation_schema)
      result   = executor.execute('mutation { echo(value: "x") }')
      expect(result[:errors]).not_to be_empty
    end

    it 'handles parent objects that are Structs (respond_to? field name)' do
      person_struct = Struct.new(:name, :age)
      alice = person_struct.new('Alice', 31)
      qt = GenQL::ObjectType.new('Query') do
        field(:me, GenQL::ObjectType.new('Person') do
                     field(:name, GenQL::StringType)
                     field(:age,  GenQL::IntType)
                   end) { |_p, _a, _c| alice }
      end
      s      = GenQL::Schema.new(query: qt)
      result = described_class.new(s).execute('{ me { name age } }')
      expect(result[:data]['me']).to eq({ 'name' => 'Alice', 'age' => 31 })
    end
  end

  describe 'cache integration' do
    subject(:exec) { described_class.new(schema, cache: GenQL::Cache.new) }

    it 'returns the correct result when cache is enabled' do
      result = exec.execute('{ greeting }')
      expect(result[:data]['greeting']).to eq 'Hello from Saratoga'
    end

    it 'serves subsequent identical queries from cache (resolver called once)' do
      call_count = 0
      counting_qt = GenQL::ObjectType.new('Query') do
        field(:ping, GenQL::StringType) do |_p, _a, _c|
          call_count += 1
          'pong'
        end
      end
      cached_exec = described_class.new(
        GenQL::Schema.new(query: counting_qt),
        cache: GenQL::Cache.new
      )

      cached_exec.execute('{ ping }')
      cached_exec.execute('{ ping }')
      expect(call_count).to eq 1
    end

    it 'does not cache mutations' do
      call_count = 0
      counting_mt = GenQL::ObjectType.new('Mutation') do
        field(:echo, GenQL::StringType) do |_p, args, _c|
          call_count += 1
          args['value']
        end
      end
      cached_exec = described_class.new(
        GenQL::Schema.new(query: query_type, mutation: counting_mt),
        cache: GenQL::Cache.new
      )

      cached_exec.execute('mutation { echo(value: "a") }')
      cached_exec.execute('mutation { echo(value: "a") }')
      expect(call_count).to eq 2
    end

    it 'treats different query strings as separate cache entries' do
      result_a = exec.execute('{ greeting }')
      result_b = exec.execute('{ people { name } }')
      expect(result_a[:data]['greeting']).to eq 'Hello from Saratoga'
      expect(result_b[:data]['people']).to be_an(Array)
    end

    it 'respects cache_ttl and re-executes after expiry' do
      call_count = 0
      counting_qt = GenQL::ObjectType.new('Query') do
        field(:tick, GenQL::IntType) do |_p, _a, _c|
          call_count += 1
          call_count
        end
      end
      cached_exec = described_class.new(
        GenQL::Schema.new(query: counting_qt),
        cache: GenQL::Cache.new
      )

      cached_exec.execute('{ tick }', cache_ttl: 0.01)
      sleep 0.05
      cached_exec.execute('{ tick }', cache_ttl: 0.01)
      expect(call_count).to eq 2
    end
  end

  describe 'context forwarding' do
    it 'passes context to the resolver' do
      received_ctx = nil
      qt = GenQL::ObjectType.new('Query') do
        field(:whoami, GenQL::StringType) { |_p, _a, ctx| received_ctx = ctx; ctx[:user] }
      end
      s = GenQL::Schema.new(query: qt)
      described_class.new(s).execute('{ whoami }', context: { user: 'alice' })
      expect(received_ctx[:user]).to eq 'alice'
    end

    it 'defaults context to an empty hash when omitted' do
      received_ctx = nil
      qt = GenQL::ObjectType.new('Query') do
        field(:ctx_check, GenQL::StringType) { |_p, _a, ctx| received_ctx = ctx; 'ok' }
      end
      s = GenQL::Schema.new(query: qt)
      described_class.new(s).execute('{ ctx_check }')
      expect(received_ctx).to eq({})
    end
  end

  describe 'nil resolver return value' do
    it 'returns nil for a nullable scalar field' do
      qt = GenQL::ObjectType.new('Query') do
        field(:maybe, GenQL::StringType) { |_p, _a, _c| nil }
      end
      s = GenQL::Schema.new(query: qt)
      result = described_class.new(s).execute('{ maybe }')
      expect(result[:data]['maybe']).to be_nil
      expect(result).not_to have_key(:errors)
    end
  end
end
