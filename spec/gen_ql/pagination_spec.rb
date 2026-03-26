# frozen_string_literal: true

require 'spec_helper'
require 'gen_ql'

RSpec.describe GenQL::Paginator do
  let(:collection) { %w[a b c d e] }

  describe '.paginate' do
    it 'returns all items when first and offset are omitted' do
      result = described_class.paginate(collection)
      expect(result.nodes).to eq collection
      expect(result.total_count).to eq 5
      expect(result.has_next_page).to be false
      expect(result.has_previous_page).to be false
    end

    it 'limits the result to first N items' do
      result = described_class.paginate(collection, first: 2)
      expect(result.nodes).to eq %w[a b]
      expect(result.total_count).to eq 5
      expect(result.has_next_page).to be true
    end

    it 'skips items before offset' do
      result = described_class.paginate(collection, offset: 2)
      expect(result.nodes).to eq %w[c d e]
      expect(result.has_previous_page).to be true
      expect(result.has_next_page).to be false
    end

    it 'applies first and offset together' do
      result = described_class.paginate(collection, first: 2, offset: 1)
      expect(result.nodes).to eq %w[b c]
      expect(result.total_count).to eq 5
      expect(result.has_next_page).to be true
      expect(result.has_previous_page).to be true
    end

    it 'returns an empty nodes array when offset exceeds the collection size' do
      result = described_class.paginate(collection, offset: 10)
      expect(result.nodes).to be_empty
      expect(result.total_count).to eq 5
      expect(result.has_next_page).to be false
    end

    it 'returns an empty nodes array when first is 0' do
      result = described_class.paginate(collection, first: 0)
      expect(result.nodes).to be_empty
      expect(result.total_count).to eq 5
      expect(result.has_next_page).to be true
    end

    it 'returns a PageResult struct' do
      result = described_class.paginate(collection)
      expect(result).to be_a(GenQL::PageResult)
    end

    it 'works with an empty collection' do
      result = described_class.paginate([])
      expect(result.nodes).to be_empty
      expect(result.total_count).to eq 0
      expect(result.has_next_page).to be false
      expect(result.has_previous_page).to be false
    end

    it 'handles first larger than the remaining items after offset' do
      result = described_class.paginate(collection, first: 10, offset: 3)
      expect(result.nodes).to eq %w[d e]
      expect(result.has_next_page).to be false
    end

    it 'returns no items when first is 0 and offset is at the end' do
      result = described_class.paginate(collection, first: 0, offset: 5)
      expect(result.nodes).to be_empty
      expect(result.has_next_page).to be false
    end

    it 'reports has_previous_page false for offset 0 with first limit' do
      result = described_class.paginate(collection, first: 2, offset: 0)
      expect(result.has_previous_page).to be false
    end
  end
end
