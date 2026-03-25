# frozen_string_literal: true

require 'spec_helper'
require 'gen_ql/lexer'

RSpec.describe GenQL::Lexer do
  subject(:lexer) { described_class.new(source) }

  def token_types(source)
    described_class.new(source).tokenize.map(&:type)
  end

  def token_values(source)
    described_class.new(source).tokenize.map(&:value)
  end

  describe '#tokenize' do
    it 'tokenizes an empty query body' do
      expect(token_types('{ }')).to eq %i[LBRACE RBRACE EOF]
    end

    it 'recognises the query keyword' do
      types = token_types('query { }')
      expect(types).to include(:QUERY)
    end

    it 'recognises the mutation keyword' do
      types = token_types('mutation { }')
      expect(types).to include(:MUTATION)
    end

    it 'recognises the subscription keyword' do
      types = token_types('subscription { }')
      expect(types).to include(:SUBSCRIPTION)
    end

    it 'tokenizes a NAME' do
      tokens = described_class.new('orchards').tokenize
      expect(tokens.first).to have_attributes(type: :NAME, value: 'orchards')
    end

    it 'tokenizes an INT literal' do
      tokens = described_class.new('42').tokenize
      expect(tokens.first).to have_attributes(type: :INT, value: 42)
    end

    it 'tokenizes a FLOAT literal' do
      tokens = described_class.new('3.14').tokenize
      expect(tokens.first).to have_attributes(type: :FLOAT, value: 3.14)
    end

    it 'tokenizes a STRING literal' do
      tokens = described_class.new('"hello"').tokenize
      expect(tokens.first).to have_attributes(type: :STRING, value: 'hello')
    end

    it 'handles escape sequences inside strings' do
      tokens = described_class.new('"line1\\nline2"').tokenize
      expect(tokens.first.value).to eq "line1\nline2"
    end

    it 'recognises true, false, null as keyword tokens' do
      types = token_types('true false null')
      expect(types).to eq %i[TRUE FALSE NULL EOF]
    end

    it 'skips line comments' do
      types = token_types("# comment\n{ }")
      expect(types).to eq %i[LBRACE RBRACE EOF]
    end

    it 'always appends an EOF token' do
      expect(token_types('').last).to eq :EOF
    end

    it 'raises LexError on unexpected character' do
      expect { described_class.new('@').tokenize }.to raise_error(GenQL::LexError)
    end

    it 'raises LexError on unterminated string' do
      expect { described_class.new('"unterminated').tokenize }.to raise_error(GenQL::LexError)
    end

    it 'tokenizes a COLON token' do
      types = token_types('key: value')
      expect(types).to include(:COLON)
    end

    it 'tokenizes LPAREN and RPAREN' do
      types = token_types('field(arg: 1)')
      expect(types).to include(:LPAREN, :RPAREN)
    end

    it 'handles multiple whitespace characters between tokens' do
      types = token_types("{    name   }")
      expect(types).to eq %i[LBRACE NAME RBRACE EOF]
    end

    it 'tokenizes negative integers' do
      tokens = described_class.new('-42').tokenize
      expect(tokens.first).to have_attributes(type: :INT, value: -42)
    end
  end
end
