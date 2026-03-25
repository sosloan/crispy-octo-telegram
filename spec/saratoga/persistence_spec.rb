# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'saratoga'

RSpec.describe Saratoga::Persistence do
  let(:tmpdir)    { Dir.mktmpdir }
  let(:data_file) { File.join(tmpdir, 'store.json') }

  after { FileUtils.remove_entry(tmpdir) }

  describe '.load' do
    it 'returns nil when path is nil' do
      expect(described_class.load(nil)).to be_nil
    end

    it 'returns nil when the file does not exist' do
      expect(described_class.load('/nonexistent/path.json')).to be_nil
    end

    it 'returns nil for a file containing invalid JSON' do
      File.write(data_file, 'not-json')
      expect(described_class.load(data_file)).to be_nil
    end

    it 'returns an empty array when harvests key is missing' do
      File.write(data_file, JSON.generate({}))
      result = described_class.load(data_file)
      expect(result).to eq([])
    end

    it 'deserialises harvests written by .save' do
      harvests = [
        Saratoga::Harvest.new(id: 'h1', orchard_id: 'o1', variety_id: 'v1',
                              quantity_kg: 500, harvested_at: '2024-08-01', notes: nil)
      ]
      described_class.save(data_file, harvests)
      loaded = described_class.load(data_file)

      expect(loaded.length).to eq 1
      h = loaded.first
      expect(h.id).to          eq 'h1'
      expect(h.orchard_id).to  eq 'o1'
      expect(h.variety_id).to  eq 'v1'
      expect(h.quantity_kg).to eq 500
      expect(h.harvested_at).to eq '2024-08-01'
      expect(h.notes).to be_nil
    end

    it 'round-trips multiple harvests' do
      harvests = [
        Saratoga::Harvest.new(id: 'h1', orchard_id: 'o1', variety_id: 'v1',
                              quantity_kg: 100, harvested_at: '2024-01-01', notes: 'first'),
        Saratoga::Harvest.new(id: 'h2', orchard_id: 'o2', variety_id: 'v2',
                              quantity_kg: 200, harvested_at: '2024-02-01', notes: nil)
      ]
      described_class.save(data_file, harvests)
      loaded = described_class.load(data_file)
      expect(loaded.map(&:id)).to eq %w[h1 h2]
    end
  end

  describe '.save' do
    it 'creates the file and parent directories if they do not exist' do
      nested_path = File.join(tmpdir, 'nested', 'dir', 'store.json')
      described_class.save(nested_path, [])
      expect(File.exist?(nested_path)).to be true
    end

    it 'writes valid JSON containing a harvests array' do
      described_class.save(data_file, [])
      parsed = JSON.parse(File.read(data_file))
      expect(parsed).to have_key('harvests')
      expect(parsed['harvests']).to eq([])
    end

    it 'is a no-op when path is nil' do
      expect { described_class.save(nil, []) }.not_to raise_error
    end
  end

  describe '.delete' do
    it 'removes an existing file' do
      File.write(data_file, '{}')
      described_class.delete(data_file)
      expect(File.exist?(data_file)).to be false
    end

    it 'is a no-op when path is nil' do
      expect { described_class.delete(nil) }.not_to raise_error
    end

    it 'is a no-op when the file does not exist' do
      expect { described_class.delete('/nonexistent.json') }.not_to raise_error
    end
  end
end

RSpec.describe Saratoga::Store do
  before { Saratoga::Store.reset! }
  after  { Saratoga::Store.reset! }

  describe '.harvests' do
    it 'returns the seed harvests on a fresh store' do
      expect(Saratoga::Store.harvests.length).to eq 4
    end

    it 'returns Harvest value objects' do
      expect(Saratoga::Store.harvests.first).to be_a(Saratoga::Harvest)
    end
  end

  describe '.add_harvest' do
    it 'persists a harvest and increases the count' do
      Saratoga::Store.add_harvest(
        orchard_id: 'o1', variety_id: 'v1',
        quantity_kg: 999, harvested_at: '2025-01-01'
      )
      expect(Saratoga::Store.harvests.length).to eq 5
    end

    it 'returns the newly created Harvest object' do
      harvest = Saratoga::Store.add_harvest(
        orchard_id: 'o1', variety_id: 'v1',
        quantity_kg: 999, harvested_at: '2025-01-01', notes: 'test note'
      )
      expect(harvest).to be_a(Saratoga::Harvest)
      expect(harvest.quantity_kg).to eq 999
      expect(harvest.notes).to eq 'test note'
    end

    it 'stores the harvest so subsequent queries see it' do
      Saratoga::Store.add_harvest(
        orchard_id: 'o1', variety_id: 'v1',
        quantity_kg: 999, harvested_at: '2025-01-01', notes: 'test note'
      )
      reloaded = Saratoga::Store.harvests
      persisted = reloaded.find { |h| h.quantity_kg == 999 }
      expect(persisted).not_to be_nil
      expect(persisted.notes).to eq 'test note'
    end

    it 'always starts from seed count after reset' do
      Saratoga::Store.reset!
      expect(Saratoga::Store.harvests.length).to eq 4
    end
  end

  describe '#reset!' do
    it 'restores the seed harvest count after bulk adds' do
      3.times do
        Saratoga::Store.add_harvest(
          orchard_id: 'o1', variety_id: 'v1',
          quantity_kg: 1, harvested_at: '2025-01-01'
        )
      end
      expect(Saratoga::Store.harvests.length).to eq 7
      Saratoga::Store.reset!
      expect(Saratoga::Store.harvests.length).to eq 4
    end
  end
end
