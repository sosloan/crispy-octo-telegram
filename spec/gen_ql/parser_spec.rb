# frozen_string_literal: true

require 'spec_helper'
require 'gen_ql/lexer'
require 'gen_ql/parser'

RSpec.describe GenQL::Parser do
  def parse(source)
    tokens = GenQL::Lexer.new(source).tokenize
    described_class.new(tokens).parse
  end

  describe '#parse' do
    it 'parses a bare selection set as a :query operation' do
      doc = parse('{ orchards }')
      expect(doc.operations.first.type).to eq :query
    end

    it 'parses an explicit query keyword' do
      doc = parse('query { orchards }')
      expect(doc.operations.first.type).to eq :query
    end

    it 'parses an explicit mutation keyword' do
      doc = parse('mutation { addHarvest }')
      expect(doc.operations.first.type).to eq :mutation
    end

    it 'captures the operation name' do
      doc = parse('query GetOrchards { orchards }')
      expect(doc.operations.first.name).to eq 'GetOrchards'
    end

    it 'builds field selections' do
      doc   = parse('{ orchards { name location } }')
      field = doc.operations.first.selections.first
      expect(field.name).to eq 'orchards'
      expect(field.selections.map(&:name)).to eq %w[name location]
    end

    it 'parses deeply nested selections' do
      doc = parse('{ orchards { varieties { name season } } }')
      orchard_field = doc.operations.first.selections.first
      variety_field = orchard_field.selections.first
      expect(variety_field.name).to eq 'varieties'
      expect(variety_field.selections.map(&:name)).to eq %w[name season]
    end

    it 'parses a field with string argument' do
      doc  = parse('{ orchard(id: "o1") { name } }')
      args = doc.operations.first.selections.first.arguments
      expect(args).to eq({ 'id' => 'o1' })
    end

    it 'parses a field with integer argument' do
      doc  = parse('{ harvest(qty: 250) { id } }')
      args = doc.operations.first.selections.first.arguments
      expect(args['qty']).to eq 250
    end

    it 'parses true/false/null literal arguments' do
      doc  = parse('{ items(active: true, draft: false, tag: null) { id } }')
      args = doc.operations.first.selections.first.arguments
      expect(args['active']).to be true
      expect(args['draft']).to be false
      expect(args['tag']).to be_nil
    end

    it 'parses multiple operations in one document' do
      doc = parse('query { orchards } mutation { addHarvest }')
      expect(doc.operations.map(&:type)).to eq %i[query mutation]
    end

    it 'raises ParseError on completely empty input' do
      expect { parse('') }.to raise_error(GenQL::ParseError)
    end

    it 'raises ParseError when closing brace is missing' do
      expect { parse('{ orchards') }.to raise_error(GenQL::ParseError)
    end
  end
end
