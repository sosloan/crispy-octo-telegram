# frozen_string_literal: true

require 'spec_helper'
require 'gen_ql'
require 'saratoga'

RSpec.describe 'Saratoga schema' do
  before { Saratoga::Store.reset! }

  let(:executor) { GenQL::Executor.new(Saratoga::SCHEMA) }

  describe 'query orchards' do
    it 'returns all orchards with basic fields' do
    it 'returns all orchards with basic fields via connection' do
      result = executor.execute('{ orchards { nodes { id name location established_year } } }')
      orchards = result[:data]['orchards']['nodes']
      expect(orchards).to be_an(Array)
      expect(orchards.length).to eq 3
      expect(orchards.map { |o| o['name'] }).to include('Saratoga Hill Block', 'Summit Ridge')
    end

    it 'returns varieties nested inside an orchard' do
      result = executor.execute('{ orchards { nodes { name varieties { name season } } } }')
      hill   = result[:data]['orchards']['nodes'].find { |o| o['name'] == 'Saratoga Hill Block' }
      expect(hill['varieties'].map { |v| v['name'] }).to include('Gravenstein', 'Pippin')
    end

    it 'returns harvests nested inside an orchard' do
      result = executor.execute('{ orchards { nodes { id harvests { id quantity_kg } } } }')
      hill   = result[:data]['orchards']['nodes'].find { |o| o['id'] == 'o1' }
      expect(hill['harvests']).not_to be_empty
    it 'returns varieties nested inside an orchard via connection' do
      result = executor.execute('{ orchards { nodes { name varieties { nodes { name season } } } } }')
      hill   = result[:data]['orchards']['nodes'].find { |o| o['name'] == 'Saratoga Hill Block' }
      expect(hill['varieties']['nodes'].map { |v| v['name'] }).to include('Gravenstein', 'Pippin')
    end

    it 'returns harvests nested inside an orchard via connection' do
      result = executor.execute('{ orchards { nodes { id harvests { nodes { id quantity_kg } } } } }')
      hill   = result[:data]['orchards']['nodes'].find { |o| o['id'] == 'o1' }
      expect(hill['harvests']['nodes']).not_to be_empty
    end

    it 'returns page_info with total_count for orchards' do
      result = executor.execute('{ orchards { page_info { total_count has_next_page has_previous_page } } }')
      page_info = result[:data]['orchards']['page_info']
      expect(page_info['total_count']).to eq 3
      expect(page_info['has_next_page']).to be false
      expect(page_info['has_previous_page']).to be false
    end

    it 'returns page_info with has_next_page false when all items fit on one page' do
      result    = executor.execute('{ orchards { page_info { has_next_page end_cursor } } }')
      page_info = result[:data]['orchards']['page_info']
      expect(page_info['has_next_page']).to be false
      expect(page_info['end_cursor']).to eq 'o3'
    end

    describe 'pagination' do
      it 'respects the first argument and sets has_next_page true when items remain' do
        result    = executor.execute('{ orchards(first: 2) { nodes { id } page_info { has_next_page end_cursor } } }')
        nodes     = result[:data]['orchards']['nodes']
        page_info = result[:data]['orchards']['page_info']
        expect(nodes.map { |o| o['id'] }).to eq %w[o1 o2]
        expect(page_info['has_next_page']).to be true
        expect(page_info['end_cursor']).to    eq 'o2'
      end

      it 'fetches the next page using the after cursor' do
        result    = executor.execute('{ orchards(first: 2, after: "o2") { nodes { id } page_info { has_next_page } } }')
        nodes     = result[:data]['orchards']['nodes']
        page_info = result[:data]['orchards']['page_info']
        expect(nodes.map { |o| o['id'] }).to eq %w[o3]
        expect(page_info['has_next_page']).to be false
      end

      it 'returns an empty nodes array and nil cursors when after points to the last item' do
        result    = executor.execute('{ orchards(first: 2, after: "o3") { nodes { id } page_info { end_cursor } } }')
        nodes     = result[:data]['orchards']['nodes']
        page_info = result[:data]['orchards']['page_info']
        expect(nodes).to be_empty
        expect(page_info['end_cursor']).to be_nil
      end

      it 'returns an empty page for an unknown or stale cursor' do
        query     = '{ orchards(first: 2, after: "invalid-cursor") ' \
                    '{ nodes { id } page_info { has_next_page end_cursor } } }'
        result    = executor.execute(query)
        nodes     = result[:data]['orchards']['nodes']
        page_info = result[:data]['orchards']['page_info']
        expect(nodes).to be_empty
        expect(page_info['has_next_page']).to be false
        expect(page_info['end_cursor']).to be_nil
      end

      it 'supports paginating through all orchards one at a time' do
        ids    = []
        cursor = nil
        loop do
          q = if cursor
                "{ orchards(first: 1, after: \"#{cursor}\") " \
                  '{ nodes { id } page_info { has_next_page end_cursor } } }'
              else
                '{ orchards(first: 1) { nodes { id } page_info { has_next_page end_cursor } } }'
              end
          result = executor.execute(q)
          conn   = result[:data]['orchards']
          ids   += conn['nodes'].map { |o| o['id'] }
          break unless conn['page_info']['has_next_page']

          cursor = conn['page_info']['end_cursor']
        end
        expect(ids).to eq %w[o1 o2 o3]
      end
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
      result = executor.execute('{ varieties { nodes { id name species } } }')
      expect(result[:data]['varieties']['nodes'].length).to eq 5
    it 'returns all varieties via connection' do
      result = executor.execute('{ varieties { nodes { id name species } } }')
      expect(result[:data]['varieties']['nodes'].length).to eq 5
    end

    it 'returns page_info with total_count for varieties' do
      result = executor.execute('{ varieties { page_info { total_count } } }')
      expect(result[:data]['varieties']['page_info']['total_count']).to eq 5
    end

    it 'fetches a single variety by id' do
      result  = executor.execute('{ variety(id: "v1") { name season } }')
      variety = result[:data]['variety']
      expect(variety['name']).to eq 'Gravenstein'
      expect(variety['season']).to eq 'early'
    end

    describe 'pagination' do
      it 'paginates varieties with first and after' do
        result    = executor.execute('{ varieties(first: 2) { nodes { id } page_info { has_next_page end_cursor } } }')
        nodes     = result[:data]['varieties']['nodes']
        page_info = result[:data]['varieties']['page_info']
        expect(nodes.map { |v| v['id'] }).to eq %w[v1 v2]
        expect(page_info['has_next_page']).to be true
        expect(page_info['end_cursor']).to    eq 'v2'
      end

      it 'returns the next page of varieties' do
        result = executor.execute('{ varieties(first: 3, after: "v2") { nodes { id } page_info { has_next_page } } }')
        nodes  = result[:data]['varieties']['nodes']
        expect(nodes.map { |v| v['id'] }).to eq %w[v3 v4 v5]
        expect(result[:data]['varieties']['page_info']['has_next_page']).to be false
      end
    end
  end

  describe 'query harvests' do
    it 'returns all recorded harvests' do
    it 'returns all recorded harvests via connection' do
      result = executor.execute('{ harvests { nodes { id orchard_id variety_id quantity_kg harvested_at } } }')
      expect(result[:data]['harvests']['nodes'].length).to eq 4
    end

    it 'returns variety details nested inside a harvest' do
      result = executor.execute('{ harvests { nodes { variety { name } } } }')
      names  = result[:data]['harvests']['nodes'].filter_map { |h| h.dig('variety', 'name') }
      result   = executor.execute('{ harvests { nodes { variety { name } } } }')
      names    = result[:data]['harvests']['nodes'].filter_map { |h| h.dig('variety', 'name') }
      expect(names).to include('Gravenstein', 'Pippin')
    end

    describe 'pagination' do
      it 'paginates harvests with first argument' do
        result    = executor.execute('{ harvests(first: 2) { nodes { id } page_info { has_next_page end_cursor } } }')
        nodes     = result[:data]['harvests']['nodes']
        page_info = result[:data]['harvests']['page_info']
        expect(nodes.length).to eq 2
        expect(page_info['has_next_page']).to be true
      end

      it 'returns remaining harvests after cursor' do
        result = executor.execute('{ harvests(first: 10, after: "h2") { nodes { id } page_info { has_next_page } } }')
        nodes  = result[:data]['harvests']['nodes']
        expect(nodes.map { |h| h['id'] }).to eq %w[h3 h4]
        expect(result[:data]['harvests']['page_info']['has_next_page']).to be false
      end
    end
  end

  describe 'pagination' do
    describe 'first argument' do
      it 'limits orchards to the requested count' do
        result = executor.execute('{ orchards(first: 2) { nodes { id } page_info { total_count has_next_page } } }')
        conn = result[:data]['orchards']
        expect(conn['nodes'].length).to eq 2
        expect(conn['page_info']['total_count']).to eq 3
        expect(conn['page_info']['has_next_page']).to be true
      end

      it 'limits varieties to the requested count' do
        result = executor.execute('{ varieties(first: 3) { nodes { id } page_info { total_count has_next_page } } }')
        conn = result[:data]['varieties']
        expect(conn['nodes'].length).to eq 3
        expect(conn['page_info']['total_count']).to eq 5
        expect(conn['page_info']['has_next_page']).to be true
      end

      it 'limits harvests to the requested count' do
        result = executor.execute('{ harvests(first: 2) { nodes { id } page_info { total_count } } }')
        conn = result[:data]['harvests']
        expect(conn['nodes'].length).to eq 2
        expect(conn['page_info']['total_count']).to eq 4
      end
    end

    describe 'offset argument' do
      it 'skips orchards before the offset' do
        all_result    = executor.execute('{ orchards { nodes { id } } }')
        paged_result  = executor.execute('{ orchards(offset: 1) { nodes { id } page_info { has_previous_page } } }')
        all_ids       = all_result[:data]['orchards']['nodes'].map { |o| o['id'] }
        paged_nodes   = paged_result[:data]['orchards']['nodes']
        expect(paged_nodes.map { |o| o['id'] }).to eq all_ids[1..]
        expect(paged_result[:data]['orchards']['page_info']['has_previous_page']).to be true
      end

      it 'combines first and offset to select a window' do
        all_result   = executor.execute('{ varieties { nodes { id } } }')
        paged_result = executor.execute('{ varieties(first: 2, offset: 1) { nodes { id } } }')
        all_ids      = all_result[:data]['varieties']['nodes'].map { |v| v['id'] }
        paged_ids    = paged_result[:data]['varieties']['nodes'].map { |v| v['id'] }
        expect(paged_ids).to eq all_ids[1, 2]
      end

      it 'returns an empty nodes list when offset exceeds collection size' do
        result = executor.execute('{ orchards(offset: 100) { nodes { id } page_info { total_count has_next_page } } }')
        conn = result[:data]['orchards']
        expect(conn['nodes']).to be_empty
        expect(conn['page_info']['total_count']).to eq 3
        expect(conn['page_info']['has_next_page']).to be false
      end
    end

    describe 'nested pagination' do
      it 'paginates varieties within an orchard' do
        result = executor.execute(
          '{ orchard(id: "o1") { varieties(first: 1) { nodes { name } page_info { total_count has_next_page } } } }'
        )
        varieties_conn = result[:data]['orchard']['varieties']
        expect(varieties_conn['nodes'].length).to eq 1
        expect(varieties_conn['page_info']['total_count']).to eq 3
        expect(varieties_conn['page_info']['has_next_page']).to be true
      end

      it 'paginates harvests within an orchard' do
        result = executor.execute(
          '{ orchard(id: "o1") { harvests(first: 1) { nodes { id } page_info { total_count has_next_page } } } }'
        )
        harvests_conn = result[:data]['orchard']['harvests']
        expect(harvests_conn['nodes'].length).to eq 1
        expect(harvests_conn['page_info']['total_count']).to eq 2
        expect(harvests_conn['page_info']['has_next_page']).to be true
      end
    end

    describe 'has_previous_page flag' do
      it 'is false when offset is 0' do
        result = executor.execute('{ orchards { page_info { has_previous_page } } }')
        expect(result[:data]['orchards']['page_info']['has_previous_page']).to be false
      end

      it 'is true when offset is greater than 0' do
        result = executor.execute('{ orchards(offset: 1) { page_info { has_previous_page } } }')
        expect(result[:data]['orchards']['page_info']['has_previous_page']).to be true
      end
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
      result = executor.execute('{ harvests { nodes { id } } }')
      expect(result[:data]['harvests']['nodes'].length).to eq 5
      result = executor.execute('{ harvests { nodes { id } page_info { total_count } } }')
      expect(result[:data]['harvests']['nodes'].length).to eq 5
      expect(result[:data]['harvests']['page_info']['total_count']).to eq 5
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

