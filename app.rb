# frozen_string_literal: true

require 'sinatra/base'
require 'sinatra/json'
require 'json'
require 'faye/websocket'
require 'securerandom'
require 'rack/utils'

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
#                    Body (batch): [ { "query": "...", "context": {...} }, ... ]
#   GET  /schema     Introspection: schema as JSON
#
# WebSocket endpoint:
#   GET  /subscriptions   Upgrade to WebSocket, then send JSON frames:
#                           { "query": "subscription { harvestAdded { ... } }" }
#                         The server pushes { "data": { ... } } frames as events fire.
# ---------------------------------------------------------------------------
class SaratogaApp < Sinatra::Base
  EXECUTOR = GenQL::Executor.new(Saratoga::SCHEMA)
  MAX_REQUEST_BYTES = Integer(ENV.fetch('MAX_REQUEST_BYTES', 1_048_576))
  MAX_QUERY_BYTES = Integer(ENV.fetch('MAX_QUERY_BYTES', 100_000))
  MAX_BATCH_SIZE = Integer(ENV.fetch('MAX_BATCH_SIZE', 20))
  MAX_SUBSCRIPTIONS = Integer(ENV.fetch('MAX_SUBSCRIPTIONS', 100))

  configure do
    set :show_exceptions, false
    set :raise_errors,    false
    set :views, File.join(__dir__, 'views')
    set :logging, true
  end

  configure :test do
    disable :protection
  end

  configure :production do
    raise 'SARATOGA_API_TOKEN must be set in production' if ENV.fetch('SARATOGA_API_TOKEN', '').empty?
  end

  before do
    headers(
      'Content-Security-Policy' => "default-src 'self'; style-src 'self' 'unsafe-inline'; " \
                                   "img-src 'self' data:; object-src 'none'; frame-ancestors 'none'",
      'Referrer-Policy' => 'no-referrer',
      'X-Content-Type-Options' => 'nosniff',
      'X-Frame-Options' => 'DENY'
    )
    request_id = request.env['HTTP_X_REQUEST_ID']
    request_id = SecureRandom.uuid unless request_id&.match?(/\A[\w.-]{1,128}\z/)
    request.env['saratoga.request_id'] = request_id
    headers 'X-Request-ID' => request_id
  end

  # Homepage (HTML for browsers) / health check (JSON for API clients)
  get '/' do
    if request.accept.any? { |a| a.to_s.include?('text/html') }
      content_type :html
      erb :homepage
    else
      json status: 'ok', service: 'Saratoga Orchards GenQL API'
    end
  end

  get '/health/live' do
    json status: 'ok'
  end

  get '/health/ready' do
    Saratoga::Database.synchronize { |db| db.execute('SELECT 1') }
    json status: 'ok'
  rescue SQLite3::Exception => e
    log_exception(e)
    halt 503, json(errors: [{ message: 'Service unavailable' }])
  end

  # Main GenQL endpoint
  post '/genql' do
    content_type :json

    halt 413, json(errors: [{ message: 'Request body too large' }]) if request.content_length.to_i > MAX_REQUEST_BYTES

    body_str = request.body.read
    halt 413, json(errors: [{ message: 'Request body too large' }]) if body_str.bytesize > MAX_REQUEST_BYTES

    payload  = JSON.parse(body_str)

    if payload.is_a?(Array)
      halt 400, json(errors: [{ message: 'Batch must contain at least one request' }]) if payload.empty?
      halt 413, json(errors: [{ message: 'Batch size limit exceeded' }]) if payload.length > MAX_BATCH_SIZE

      results = payload.map { |item| execute_query_item(item) }
      json results
    else
      halt 400, json(errors: [{ message: 'Request body must be a JSON object or array' }]) unless payload.is_a?(Hash)

      query = validate_query!(payload)
      context = payload.fetch('context', {})
      raise GenQL::ExecutionError, 'context must be a JSON object' unless context.is_a?(Hash)

      authorize_mutation!(query)
      json EXECUTOR.execute(query, context: context)
    end
  rescue JSON::ParserError => e
    halt 400, json(errors: [{ message: "Invalid JSON: #{e.message}" }])
  rescue GenQL::LexError, GenQL::ParseError, GenQL::ExecutionError => e
    halt 400, json(errors: [{ message: e.message }])
  rescue StandardError => e
    log_exception(e)
    halt 500, json(errors: [{ message: 'Internal server error' }])
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
      unless payload.is_a?(Hash)
        ws.send(JSON.generate({ errors: [{ message: 'Message must be a JSON object' }] }))
        next
      end

      query = validate_query!(payload)
      ctx     = payload.fetch('context', {})
      if subscription_ids.length >= MAX_SUBSCRIPTIONS
        ws.send(JSON.generate({ errors: [{ message: 'Subscription limit exceeded' }] }))
        next
      end

      ids = EXECUTOR.subscribe(query, context: ctx) do |result|
        ws.send(JSON.generate(result))
      end
      subscription_ids.concat(ids)
      ws.send(JSON.generate({ subscribed: true, count: ids.length }))
    rescue JSON::ParserError => e
      ws.send(JSON.generate({ errors: [{ message: "Invalid JSON: #{e.message}" }] }))
    rescue GenQL::LexError, GenQL::ParseError, GenQL::ExecutionError => e
      ws.send(JSON.generate({ errors: [{ message: e.message }] }))
    rescue StandardError => e
      log_exception(e)
      ws.send(JSON.generate({ errors: [{ message: 'Internal subscription error' }] }))
    end

    ws.on :close do |_event|
      subscription_ids.each { |id| GenQL::SubscriptionBroker.unsubscribe(id) }
      subscription_ids.clear
    end

    ws.rack_response
  end

  # Introspection: describe the schema in plain JSON
  get '/schema' do
    schema_types = [Saratoga::QueryType, Saratoga::MutationType, Saratoga::SubscriptionType,
                    Saratoga::OrchardType, Saratoga::VarietyType, Saratoga::HarvestType,
                    Saratoga::OrchardsConnection, Saratoga::VarietiesConnection,
                    Saratoga::HarvestsConnection, Saratoga::VarietiesInOrchardConnection,
                    Saratoga::HarvestsInOrchardConnection, GenQL::PageInfoType]
    types = {}
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

  private

  def execute_query_item(item)
    return { errors: [{ message: 'Request item must be a JSON object' }] } unless item.is_a?(Hash)

    query = validate_query!(item)
    context = item.fetch('context', {})
    raise GenQL::ExecutionError, 'context must be a JSON object' unless context.is_a?(Hash)

    authorize_mutation!(query)
    EXECUTOR.execute(query, context: context)
  rescue GenQL::LexError, GenQL::ParseError, GenQL::ExecutionError => e
    { errors: [{ message: e.message }] }
  rescue StandardError => e
    log_exception(e)
    { errors: [{ message: 'Internal server error' }] }
  end

  def validate_query!(item)
    query = item['query']
    raise GenQL::ExecutionError, 'Missing required field: query' unless query.is_a?(String) && !query.strip.empty?
    raise GenQL::ExecutionError, 'Query size limit exceeded' if query.bytesize > MAX_QUERY_BYTES

    query
  end

  def log_exception(error)
    logger.error(
      "request_id=#{request.env['saratoga.request_id']} " \
      "#{error.class}: #{error.message}"
    )
  end

  def authorize_mutation!(query)
    return unless mutation_query?(query)

    token = ENV.fetch('SARATOGA_API_TOKEN', '')
    supplied = request.env.fetch('HTTP_AUTHORIZATION', '').delete_prefix('Bearer ')
    authorized = !token.empty? && supplied.bytesize == token.bytesize && Rack::Utils.secure_compare(supplied, token)
    return if authorized

    headers 'WWW-Authenticate' => 'Bearer'
    halt 401, json(errors: [{ message: 'Authentication required for mutations' }])
  end

  def mutation_query?(query)
    tokens = GenQL::Lexer.new(query).tokenize
    GenQL::Parser.new(tokens).parse.operations.any? { |operation| operation.type.to_s == 'mutation' }
  end
end
