# frozen_string_literal: true

require 'sinatra/base'
require 'sinatra/json'
require 'json'

$LOAD_PATH.unshift(File.join(__dir__, 'lib'))

require 'gen_ql'
require 'saratoga'

# ---------------------------------------------------------------------------
# Saratoga Orchards — GenQL HTTP server
#
# Exposes a single endpoint:
#   POST /genql   Content-Type: application/json
#                 Body: { "query": "...", "context": {...} }
#
# Returns:
#   200  { "data": {...} }
#   200  { "data": {...}, "errors": [...] }   (partial success)
#   400  { "errors": [{ "message": "..." }] } (parse / request errors)
# ---------------------------------------------------------------------------
class SaratogaApp < Sinatra::Base
  EXECUTOR = GenQL::Executor.new(Saratoga::SCHEMA)

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

    halt 400, json(errors: [{ message: 'Missing required field: query' }]) unless payload.key?('query')

    result = EXECUTOR.execute(
      payload['query'],
      context: payload.fetch('context', {})
    )

    json result
  rescue JSON::ParserError => e
    halt 400, json(errors: [{ message: "Invalid JSON: #{e.message}" }])
  rescue GenQL::LexError, GenQL::ParseError => e
    halt 400, json(errors: [{ message: e.message }])
  rescue StandardError => e
    halt 500, json(errors: [{ message: "Internal server error: #{e.message}" }])
  end

  # Introspection: describe the schema in plain JSON
  get '/schema' do
    types = {}
    [Saratoga::QueryType, Saratoga::MutationType,
     Saratoga::OrchardType, Saratoga::VarietyType,
     Saratoga::HarvestType].each do |type|
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
