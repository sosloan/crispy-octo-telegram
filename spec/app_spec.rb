# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require_relative '../app'

RSpec.describe SaratogaApp do
  include Rack::Test::Methods

  def app
    SaratogaApp
  end

  before { Saratoga::Store.reset! }

  describe 'GET /' do
    it 'returns 200 with service status' do
      get '/'
      expect(last_response.status).to eq 200
      body = JSON.parse(last_response.body)
      expect(body['status']).to eq 'ok'
    end
  end

  describe 'GET /schema' do
    it 'returns 200 with schema description' do
      get '/schema'
      expect(last_response.status).to eq 200
      body = JSON.parse(last_response.body)
      expect(body['schema']).to include('Orchard', 'Variety', 'Harvest')
    end
  end

  describe 'POST /genql' do
    def post_genql(query, context: {})
      post '/genql',
           JSON.generate({ 'query' => query, 'context' => context }),
           'CONTENT_TYPE' => 'application/json'
    end

    it 'returns 200 with data for a valid query' do
      post_genql('{ orchards { name } }')
      expect(last_response.status).to eq 200
      body = JSON.parse(last_response.body)
      expect(body['data']['orchards']).to be_an(Array)
    end

    it 'returns 400 when the query key is missing' do
      post '/genql', JSON.generate({}), 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq 400
      body = JSON.parse(last_response.body)
      expect(body['errors'].first['message']).to match(/query/)
    end

    it 'returns 400 for malformed JSON' do
      post '/genql', 'not-json', 'CONTENT_TYPE' => 'application/json'
      expect(last_response.status).to eq 400
    end

    it 'returns 400 for a lex error in the query' do
      post_genql('{ @invalid }')
      expect(last_response.status).to eq 400
    end

    it 'returns 400 for a parse error in the query' do
      post_genql('{ unclosed')
      expect(last_response.status).to eq 400
    end

    it 'executes a mutation via POST' do
      q = 'mutation { addHarvest(orchard_id: "o1", variety_id: "v1", ' \
          'quantity_kg: 500, harvested_at: "2024-08-01") { id quantity_kg } }'
      post_genql(q)
      expect(last_response.status).to eq 200
      body    = JSON.parse(last_response.body)
      harvest = body['data']['addHarvest']
      expect(harvest['quantity_kg']).to eq 500
    end

    it 'returns nested orchard data' do
      post_genql('{ orchards { name varieties { name } } }')
      expect(last_response.status).to eq 200
      orchards = JSON.parse(last_response.body)['data']['orchards']
      expect(orchards.first['varieties']).to be_an(Array)
    end
  end
end
