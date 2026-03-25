# frozen_string_literal: true

require 'spec_helper'
require 'gen_ql'

RSpec.describe GenQL::ObjectType do
  describe '.new' do
    it 'stores the type name as a string' do
      type = described_class.new('Orchard') {}
      expect(type.name).to eq 'Orchard'
    end

    it 'stores an optional description' do
      type = described_class.new('Orchard', description: 'A fruit orchard') {}
      expect(type.description).to eq 'A fruit orchard'
    end

    it 'starts with an empty fields hash' do
      type = described_class.new('Empty') {}
      expect(type.fields).to eq({})
    end

    it 'registers fields declared in the block' do
      type = described_class.new('Person') do
        field :name, GenQL::StringType
        field :age,  GenQL::IntType
      end
      expect(type.fields.keys).to contain_exactly('name', 'age')
    end

    it 'converts symbol field names to strings' do
      type = described_class.new('T') { field :title, GenQL::StringType }
      expect(type.fields).to have_key('title')
    end
  end

  describe '#field' do
    let(:type) do
      described_class.new('T') do
        field :score, GenQL::FloatType, description: 'A score' do |obj, _args, _ctx|
          obj[:score]
        end
      end
    end

    it 'stores the field description' do
      expect(type.fields['score'].description).to eq 'A score'
    end

    it 'stores the field type' do
      expect(type.fields['score'].type).to eq GenQL::FloatType
    end

    it 'stores the resolver block' do
      expect(type.fields['score'].resolver).to be_a(Proc)
    end

    it 'creates a FieldDefinition with the correct name' do
      expect(type.fields['score']).to be_a(GenQL::FieldDefinition)
      expect(type.fields['score'].name).to eq 'score'
    end
  end
end

RSpec.describe GenQL::Schema do
  let(:query_type)    { GenQL::ObjectType.new('Query') {} }
  let(:mutation_type) { GenQL::ObjectType.new('Mutation') {} }
  let(:sub_type)      { GenQL::ObjectType.new('Subscription') {} }

  it 'exposes the query type' do
    schema = described_class.new(query: query_type)
    expect(schema.query_type).to eq query_type
  end

  it 'exposes the mutation type when provided' do
    schema = described_class.new(query: query_type, mutation: mutation_type)
    expect(schema.mutation_type).to eq mutation_type
  end

  it 'returns nil mutation_type when not provided' do
    schema = described_class.new(query: query_type)
    expect(schema.mutation_type).to be_nil
  end

  it 'exposes the subscription type when provided' do
    schema = described_class.new(query: query_type, subscription: sub_type)
    expect(schema.subscription_type).to eq sub_type
  end

  it 'returns nil subscription_type when not provided' do
    schema = described_class.new(query: query_type)
    expect(schema.subscription_type).to be_nil
  end
end

RSpec.describe 'GenQL scalar types' do
  it 'StringType has name "String"' do
    expect(GenQL::StringType.name).to eq 'String'
  end

  it 'IntType has name "Int"' do
    expect(GenQL::IntType.name).to eq 'Int'
  end

  it 'FloatType has name "Float"' do
    expect(GenQL::FloatType.name).to eq 'Float'
  end

  it 'BooleanType has name "Boolean"' do
    expect(GenQL::BooleanType.name).to eq 'Boolean'
  end

  it 'IDType has name "ID"' do
    expect(GenQL::IDType.name).to eq 'ID'
  end

  it 'all scalar types extend GenQL::Scalar' do
    scalars = [GenQL::StringType, GenQL::IntType, GenQL::FloatType,
               GenQL::BooleanType, GenQL::IDType]
    expect(scalars).to all(be_a(GenQL::Scalar))
  end
end

RSpec.describe 'GenQL.connection_type' do
  let(:node_type) { GenQL::ObjectType.new('Item') { field :id, GenQL::IDType } }
  subject(:conn)  { GenQL.connection_type('ItemsConnection', node_type, description: 'Paginated items') }

  it 'returns an ObjectType' do
    expect(conn).to be_a(GenQL::ObjectType)
  end

  it 'has the given name' do
    expect(conn.name).to eq 'ItemsConnection'
  end

  it 'has a nodes field' do
    expect(conn.fields).to have_key('nodes')
  end

  it 'has a page_info field' do
    expect(conn.fields).to have_key('page_info')
  end

  it 'nodes field resolves to PageResult#nodes' do
    page = GenQL::PageResult.new(%w[a b], 2, false, false)
    nodes_field = conn.fields['nodes']
    expect(nodes_field.resolver.call(page, {}, {})).to eq %w[a b]
  end

  it 'page_info field resolves the PageResult itself' do
    page = GenQL::PageResult.new([], 0, false, false)
    page_info_field = conn.fields['page_info']
    expect(page_info_field.resolver.call(page, {}, {})).to eq page
  end
end
