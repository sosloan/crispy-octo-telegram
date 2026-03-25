# frozen_string_literal: true

require 'spec_helper'
require 'gen_ql'
require 'saratoga'

RSpec.describe 'Saratoga schema' do
  before { Saratoga::Store.reset! }

  let(:executor) { GenQL::Executor.new(Saratoga::SCHEMA) }

  describe 'query orchards' do
    it 'returns all orchards with basic fields' do
      result = executor.execute('{ orchards { id name location established_year } }')
      orchards = result[:data]['orchards']
      expect(orchards).to be_an(Array)
      expect(orchards.length).to eq 3
      expect(orchards.map { |o| o['name'] }).to include('Saratoga Hill Block', 'Summit Ridge')
    end

    it 'returns varieties nested inside an orchard' do
      result = executor.execute('{ orchards { name varieties { name season } } }')
      hill   = result[:data]['orchards'].find { |o| o['name'] == 'Saratoga Hill Block' }
      expect(hill['varieties'].map { |v| v['name'] }).to include('Gravenstein', 'Pippin')
    end

    it 'returns harvests nested inside an orchard' do
      result = executor.execute('{ orchards { id harvests { id quantity_kg } } }')
      hill   = result[:data]['orchards'].find { |o| o['id'] == 'o1' }
      expect(hill['harvests']).not_to be_empty
    end
  end

  describe 'query orchard by id' do
    it 'returns a single orchard matching the id' do
      result  = executor.execute('{ orchard(id: "o1") { name location } }')
      orchard = result[:data]['orchard']
      expect(orchard['name']).to eq 'Saratoga Hill Block'
    end

    it 'returns nil for unknown id' do
      result = executor.execute('{ orchard(id: "zzz") { name } }')
      expect(result[:data]['orchard']).to be_nil
    end
  end

  describe 'query varieties' do
    it 'returns all varieties' do
      result = executor.execute('{ varieties { id name species } }')
      expect(result[:data]['varieties'].length).to eq 5
    end

    it 'fetches a single variety by id' do
      result  = executor.execute('{ variety(id: "v1") { name season } }')
      variety = result[:data]['variety']
      expect(variety['name']).to eq 'Gravenstein'
      expect(variety['season']).to eq 'early'
    end
  end

  describe 'query harvests' do
    it 'returns all recorded harvests' do
      result = executor.execute('{ harvests { id orchard_id variety_id quantity_kg harvested_at } }')
      expect(result[:data]['harvests'].length).to eq 4
    end

    it 'returns variety details nested inside a harvest' do
      result   = executor.execute('{ harvests { variety { name } } }')
      names    = result[:data]['harvests'].filter_map { |h| h.dig('variety', 'name') }
      expect(names).to include('Gravenstein', 'Pippin')
    end
  end

  describe 'mutation addHarvest' do
    it 'adds a new harvest and returns its fields' do
      query = <<~GQL
        mutation {
          addHarvest(
            orchard_id: "o2",
            variety_id: "v2",
            quantity_kg: 350,
            harvested_at: "2024-09-01"
          ) {
            id
            orchard_id
            variety_id
            quantity_kg
            harvested_at
          }
        }
      GQL

      result  = executor.execute(query)
      harvest = result[:data]['addHarvest']
      expect(harvest['orchard_id']).to  eq 'o2'
      expect(harvest['variety_id']).to  eq 'v2'
      expect(harvest['quantity_kg']).to eq 350
      expect(harvest['harvested_at']).to eq '2024-09-01'
      expect(harvest['id']).not_to be_nil
    end

    it 'persists the new harvest so subsequent queries see it' do
      mutation = 'mutation { addHarvest(orchard_id: "o1", variety_id: "v3", ' \
                 'quantity_kg: 100, harvested_at: "2024-10-01") { id } }'
      executor.execute(mutation)
      result = executor.execute('{ harvests { id } }')
      expect(result[:data]['harvests'].length).to eq 5
    end
  end

  describe 'error handling' do
    it 'returns an error for an unknown field on the root query type' do
      result = executor.execute('{ unknownField }')
      expect(result[:errors]).not_to be_empty
    end
  end

  describe 'subscription harvestAdded' do
    before { GenQL::SubscriptionBroker.reset! }
    after  { GenQL::SubscriptionBroker.reset! }

    it 'delivers a harvest payload when addHarvest mutation fires' do
      payloads = []
      executor.subscribe('subscription { harvestAdded { id orchard_id quantity_kg } }') do |r|
        payloads << r
      end

      mutation = 'mutation { addHarvest(orchard_id: "o1", variety_id: "v1", ' \
                 'quantity_kg: 700, harvested_at: "2024-08-15") { id } }'
      executor.execute(mutation)

      expect(payloads.length).to eq 1
      event = payloads.first[:data]['harvestAdded']
      expect(event['orchard_id']).to eq 'o1'
      expect(event['quantity_kg']).to eq 700
    end

    it 'delivers nested variety details when requested in the subscription' do
      payloads = []
      executor.subscribe('subscription { harvestAdded { id variety { name } } }') do |r|
        payloads << r
      end

      mutation = 'mutation { addHarvest(orchard_id: "o1", variety_id: "v1", ' \
                 'quantity_kg: 300, harvested_at: "2024-08-20") { id } }'
      executor.execute(mutation)

      expect(payloads.length).to eq 1
      event = payloads.first[:data]['harvestAdded']
      expect(event.dig('variety', 'name')).to eq 'Gravenstein'
    end

    it 'stops delivering after unsubscribing' do
      payloads = []
      ids = executor.subscribe('subscription { harvestAdded { id } }') { |r| payloads << r }
      ids.each { |id| GenQL::SubscriptionBroker.unsubscribe(id) }

      mutation = 'mutation { addHarvest(orchard_id: "o1", variety_id: "v1", ' \
                 'quantity_kg: 100, harvested_at: "2024-08-01") { id } }'
      executor.execute(mutation)

      expect(payloads).to be_empty
    end
  end
end
