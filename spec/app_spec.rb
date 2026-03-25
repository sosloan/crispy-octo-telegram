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

    it 'returns 200 with connection data for a valid query' do
      post_genql('{ orchards { nodes { name } } }')
      expect(last_response.status).to eq 200
      body = JSON.parse(last_response.body)
      expect(body['data']['orchards']['nodes']).to be_an(Array)
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

    it 'returns nested connection data for an orchard' do
      post_genql('{ orchards { nodes { name varieties { nodes { name } } } } }')
      expect(last_response.status).to eq 200
      orchards = JSON.parse(last_response.body)['data']['orchards']['nodes']
      expect(orchards.first['varieties']['nodes']).to be_an(Array)
    end
  end

  describe 'POST /genql (batch)' do
    def post_batch(queries)
      post '/genql',
           JSON.generate(queries),
           'CONTENT_TYPE' => 'application/json'
    end

    it 'returns an array of results for a batch request' do
      post_batch([
                   { 'query' => '{ orchards { nodes { name } } }' },
                   { 'query' => '{ varieties { nodes { name } } }' }
                 ])
      expect(last_response.status).to eq 200
      body = JSON.parse(last_response.body)
      expect(body).to be_an(Array)
      expect(body.length).to eq 2
      expect(body[0]['data']['orchards']['nodes']).to be_an(Array)
      expect(body[1]['data']['varieties']['nodes']).to be_an(Array)
    end

    it 'processes each query independently in a batch' do
      post_batch([
                   { 'query' => '{ orchards { nodes { name } } }' },
                   { 'query' => '{ varieties { nodes { name season } } }' }
                 ])
      body = JSON.parse(last_response.body)
      expect(body[0]['data']).to have_key('orchards')
      expect(body[1]['data']).to have_key('varieties')
    end

    it 'returns an error entry for an invalid query in a batch without aborting others' do
      post_batch([
                   { 'query' => '{ orchards { nodes { name } } }' },
                   { 'query' => '{ @invalid }' },
                   { 'query' => '{ varieties { nodes { name } } }' }
                 ])
      expect(last_response.status).to eq 200
      body = JSON.parse(last_response.body)
      expect(body).to be_an(Array)
      expect(body.length).to eq 3
      expect(body[0]['data']['orchards']['nodes']).to be_an(Array)
      expect(body[1]['errors']).not_to be_nil
      expect(body[2]['data']['varieties']['nodes']).to be_an(Array)
    end

    it 'returns an error entry when query key is missing in a batch item' do
      post_batch([
                   { 'query' => '{ orchards { nodes { name } } }' },
                   { 'context' => {} }
                 ])
      expect(last_response.status).to eq 200
      body = JSON.parse(last_response.body)
      expect(body[1]['errors'].first['message']).to match(/query/)
    end

    it 'returns an empty array for an empty batch' do
      post_batch([])
      expect(last_response.status).to eq 200
      body = JSON.parse(last_response.body)
      expect(body).to eq []
    end

    it 'supports context per batch item' do
      post_batch([{ 'query' => '{ orchards { nodes { name } } }',
                    'context' => { 'user' => 'admin' } }])
      expect(last_response.status).to eq 200
      body = JSON.parse(last_response.body)
      expect(body[0]['data']['orchards']['nodes']).to be_an(Array)
    end
  end
end
