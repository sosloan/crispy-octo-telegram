# frozen_string_literal: true

require 'date'
require_relative '../gen_ql'
require_relative 'store'

module Saratoga
  VarietyType = GenQL::ObjectType.new('Variety', description: 'A named apple variety') do
    field :id,      GenQL::IDType,     description: 'Unique identifier'
    field :name,    GenQL::StringType, description: 'Variety name'
    field :species, GenQL::StringType, description: 'Botanical species name'
    field :season,  GenQL::StringType, description: 'Harvest season (early/mid/late)'
    field :notes,   GenQL::StringType, description: 'Tasting or cultivation notes'
  end

  HarvestType = GenQL::ObjectType.new('Harvest', description: 'A recorded harvest event') do
    field :id,           GenQL::IDType,     description: 'Unique identifier'
    field :orchard_id,   GenQL::IDType,     description: 'Parent orchard id'
    field :variety_id,   GenQL::IDType,     description: 'Harvested variety id'
    field :quantity_kg,  GenQL::IntType,    description: 'Quantity in kilograms'
    field :harvested_at, GenQL::StringType, description: 'ISO-8601 harvest date'
    field :notes,        GenQL::StringType, description: 'Optional harvest notes'

    field :variety, VarietyType, description: 'Variety details' do |harvest, _args, _ctx|
      harvest.variety
    end
  end

  VarietiesInOrchardConnection = GenQL.connection_type(
    'VarietiesInOrchardConnection', VarietyType,
    description: 'Paginated varieties within an orchard'
  )
  HarvestsInOrchardConnection = GenQL.connection_type(
    'HarvestsInOrchardConnection', HarvestType,
    description: 'Paginated harvests within an orchard'
  )

  OrchardType = GenQL::ObjectType.new('Orchard', description: 'A named orchard block') do
    field :id,               GenQL::IDType,     description: 'Unique identifier'
    field :name,             GenQL::StringType, description: 'Orchard block name'
    field :location,         GenQL::StringType, description: 'Geographic location'
    field :established_year, GenQL::IntType,    description: 'Year the block was planted'

    field :varieties, VarietiesInOrchardConnection,
          description: 'Paginated apple varieties grown in this orchard' do |orchard, args, _ctx|
      GenQL::Paginator.paginate(
        orchard.varieties,
        first: args['first'],
        offset: args['offset'],
        after: args['after']
      )
    end

    field :harvests, HarvestsInOrchardConnection,
          description: 'Paginated harvests recorded for this orchard' do |orchard, args, _ctx|
      GenQL::Paginator.paginate(
        Store.harvests.select { |harvest| harvest.orchard_id == orchard.id },
        first: args['first'],
        offset: args['offset'],
        after: args['after']
      )
    end
  end

  OrchardConnection = GenQL.connection_type(
    'OrchardConnection', OrchardType,
    description: 'Paginated list of orchards'
  )
  VarietyConnection = GenQL.connection_type(
    'VarietyConnection', VarietyType,
    description: 'Paginated list of varieties'
  )
  HarvestConnection = GenQL.connection_type(
    'HarvestConnection', HarvestType,
    description: 'Paginated list of harvests'
  )

  QueryType = GenQL::ObjectType.new('Query') do
    field :orchards, OrchardConnection, description: 'Paginated list of all orchards' do |_parent, args, _ctx|
      GenQL::Paginator.paginate(
        Store.orchards,
        first: args['first'],
        offset: args['offset'],
        after: args['after']
      )
    end

    field :orchard, OrchardType, description: 'Fetch a single orchard by id' do |_parent, args, _ctx|
      Store.orchards.find { |orchard| orchard.id == args['id'] }
    end

    field :varieties, VarietyConnection, description: 'Paginated list of all varieties' do |_parent, args, _ctx|
      GenQL::Paginator.paginate(
        Store.varieties,
        first: args['first'],
        offset: args['offset'],
        after: args['after']
      )
    end

    field :variety, VarietyType, description: 'Fetch a single variety by id' do |_parent, args, _ctx|
      Store.varieties.find { |variety| variety.id == args['id'] }
    end

    field :harvests, HarvestConnection, description: 'Paginated list of all harvests' do |_parent, args, _ctx|
      GenQL::Paginator.paginate(
        Store.harvests,
        first: args['first'],
        offset: args['offset'],
        after: args['after']
      )
    end
  end

  MutationType = GenQL::ObjectType.new('Mutation') do
    field :addHarvest, HarvestType, description: 'Record a new harvest' do |_parent, args, _ctx|
      orchard = Store.orchards.find { |item| item.id == args['orchard_id'] }
      variety = Store.varieties.find { |item| item.id == args['variety_id'] }
      quantity = args['quantity_kg']

      raise GenQL::ExecutionError, 'Unknown orchard_id' unless orchard
      raise GenQL::ExecutionError, 'Unknown variety_id' unless variety
      raise GenQL::ExecutionError, 'quantity_kg must be a positive integer' unless quantity.is_a?(Integer) && quantity.positive?

      begin
        Date.iso8601(args['harvested_at'].to_s)
      rescue Date::Error
        raise GenQL::ExecutionError, 'harvested_at must be an ISO-8601 date'
      end

      harvest = Store.add_harvest(
        orchard_id: orchard.id,
        variety_id: variety.id,
        quantity_kg: quantity,
        harvested_at: args['harvested_at'],
        notes: args['notes']
      )
      GenQL::SubscriptionBroker.publish('harvestAdded', harvest)
      harvest
    end
  end

  SubscriptionType = GenQL::ObjectType.new('Subscription') do
    field :harvestAdded, HarvestType, description: 'Fired whenever a new harvest is recorded'
  end

  SCHEMA = GenQL::Schema.new(query: QueryType, mutation: MutationType, subscription: SubscriptionType)
end
