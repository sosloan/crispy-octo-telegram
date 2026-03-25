# frozen_string_literal: true

require 'sinatra/base'
require 'sinatra/json'
require 'json'
require 'faye/websocket'

$LOAD_PATH.unshift(File.join(__dir__, 'lib'))

require 'gen_ql'
require 'saratoga'

# ---------------------------------------------------------------------------
# Saratoga Orchards — GenQL HTTP + WebSocket server
#
# HTTP endpoints:
#   GET  /           Health check
#   POST /genql      Execute a query or mutation
#                    Body: { "query": "...", "context": {...} }
#   GET  /schema     Introspection: schema as JSON
#
# WebSocket endpoint:
#   GET  /subscriptions   Upgrade to WebSocket, then send JSON frames:
#                           { "query": "subscription { harvestAdded { ... } }" }
#                         The server pushes { "data": { ... } } frames as events fire.
# Exposes a single endpoint:
#   POST /genql   Content-Type: application/json
#                 Body (single):  { "query": "...", "context": {...} }
#                 Body (batch):   [ { "query": "...", "context": {...} }, ... ]
#
# Returns (single):
#   200  { "data": {...} }
#   200  { "data": {...}, "errors": [...] }   (partial success)
#   400  { "errors": [{ "message": "..." }] } (parse / request errors)
#
# Returns (batch):
#   200  [ { "data": {...} }, { "data": {...}, "errors": [...] }, ... ]
# ---------------------------------------------------------------------------
class SaratogaApp < Sinatra::Base
  EXECUTOR = GenQL::Executor.new(Saratoga::SCHEMA)

  # Enable JSON persistence: store harvests in data/store.json relative to
  # this file so the server retains mutations across restarts without needing
  # an external database.
  Saratoga::Store.data_file =
    ENV.fetch('SARATOGA_DATA_FILE', File.join(__dir__, 'data', 'store.json'))

  configure do
    set :show_exceptions, false
    set :raise_errors,    false
  end

  # Health check
  get '/' do
    json status: 'ok', service: 'Saratoga Orchards GenQL API'
  end

  # Main GenQL endpoint
  post '/genql' do
    content_type :json

    body_str = request.body.read
    payload  = JSON.parse(body_str)

    if payload.is_a?(Array)
      results = payload.map { |item| execute_query_item(item) }
      json results
    else
      halt 400, json(errors: [{ message: 'Missing required field: query' }]) unless payload.key?('query')

      result = EXECUTOR.execute(
        payload['query'],
        context: payload.fetch('context', {})
      )

      json result
    end
  rescue JSON::ParserError => e
    halt 400, json(errors: [{ message: "Invalid JSON: #{e.message}" }])
  rescue GenQL::LexError, GenQL::ParseError => e
    halt 400, json(errors: [{ message: e.message }])
  rescue StandardError => e
    halt 500, json(errors: [{ message: "Internal server error: #{e.message}" }])
  end

  # WebSocket subscription endpoint
  get '/subscriptions' do
    unless Faye::WebSocket.websocket?(request.env)
      halt 400, json(errors: [{ message: 'WebSocket upgrade required' }])
    end

    ws = Faye::WebSocket.new(request.env)
    subscription_ids = []

    ws.on :message do |event|
      payload = JSON.parse(event.data)
      query   = payload['query']
      ctx     = payload.fetch('context', {})

      ids = EXECUTOR.subscribe(query, context: ctx) do |result|
        ws.send(JSON.generate(result))
      end
      subscription_ids.concat(ids)
      ws.send(JSON.generate({ subscribed: true, count: ids.length }))
    rescue JSON::ParserError => e
      ws.send(JSON.generate({ errors: [{ message: "Invalid JSON: #{e.message}" }] }))
    rescue GenQL::LexError, GenQL::ParseError, GenQL::ExecutionError => e
      ws.send(JSON.generate({ errors: [{ message: e.message }] }))
    end

    ws.on :close do |_event|
      subscription_ids.each { |id| GenQL::SubscriptionBroker.unsubscribe(id) }
      subscription_ids.clear
    end

    ws.rack_response
  private

  def execute_query_item(item)
    return { errors: [{ message: 'Missing required field: query' }] } unless item.key?('query')

    EXECUTOR.execute(item['query'], context: item.fetch('context', {}))
  rescue GenQL::LexError, GenQL::ParseError => e
    { errors: [{ message: e.message }] }
  rescue StandardError => e
    { errors: [{ message: "Internal server error: #{e.message}" }] }
  end

  # Introspection: describe the schema in plain JSON
  get '/schema' do
    types = {}
    [Saratoga::QueryType, Saratoga::MutationType,
     Saratoga::OrchardType, Saratoga::VarietyType, Saratoga::HarvestType,
     Saratoga::OrchardsConnection, Saratoga::VarietiesConnection, Saratoga::HarvestsConnection,
     Saratoga::VarietiesInOrchardConnection, Saratoga::HarvestsInOrchardConnection,
     GenQL::PageInfoType].each do |type|
    schema_types = [Saratoga::QueryType, Saratoga::MutationType, Saratoga::SubscriptionType,
                    Saratoga::OrchardType, Saratoga::VarietyType, Saratoga::HarvestType]
    schema_types.each do |type|
      types[type.name] = {
        description: type.description,
        fields: type.fields.transform_values do |f|
          { type: f.type.name, description: f.description }
        end
      }
    end
    json schema: types
  end
end
