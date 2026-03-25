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
end
