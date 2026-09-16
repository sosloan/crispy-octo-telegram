# frozen_string_literal: true

require_relative '../gen_ql'
require_relative 'store'

module Saratoga
  # ---------------------------------------------------------------------------
  # GenQL type definitions for the Saratoga Orchards domain
  # ---------------------------------------------------------------------------

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

  # Connection types for nested lists inside an orchard must be defined before
  # OrchardType so they can be referenced as field types.  The food-truck
  # connection is backfilled with its node type once FoodTruckType exists.
  VarietiesInOrchardConnection = GenQL.connection_type(
    'VarietiesInOrchardConnection', VarietyType,
    description: 'Paginated varieties within an orchard'
  )
  HarvestsInOrchardConnection = GenQL.connection_type(
    'HarvestsInOrchardConnection', HarvestType,
    description: 'Paginated harvests within an orchard'
  )
  FoodTrucksInOrchardConnection = GenQL.connection_type(
    'FoodTrucksInOrchardConnection', VarietyType,
    description: 'Paginated food trucks within an orchard'
  )

  OrchardType = GenQL::ObjectType.new('Orchard', description: 'A named orchard block') do
    field :id,               GenQL::IDType,     description: 'Unique identifier'
    field :name,             GenQL::StringType, description: 'Orchard block name'
    field :location,         GenQL::StringType, description: 'Geographic location'
    field :established_year, GenQL::IntType,    description: 'Year the block was planted'

    field :varieties, VarietiesInOrchardConnection,
          description: 'Paginated apple varieties grown in this orchard' do |orchard, args, _ctx|
      GenQL::Paginator.paginate(orchard.varieties,
                                first: args['first'],
                                offset: args['offset'] || 0)
    end

    field :harvests, HarvestsInOrchardConnection,
          description: 'Paginated harvests recorded for this orchard' do |orchard, args, _ctx|
      collection = Store.harvests.select { |h| h.orchard_id == orchard.id }
      GenQL::Paginator.paginate(collection,
                                first: args['first'],
                                offset: args['offset'] || 0)
    end

    field :food_trucks, FoodTrucksInOrchardConnection,
          description: 'Paginated food truck stalls hosted by this orchard' do |orchard, args, _ctx|
      collection = Store.food_trucks.select { |ft| ft.orchard_id == orchard.id }
      GenQL::Paginator.paginate(collection,
                                first: args['first'],
                                offset: args['offset'] || 0)
    end
  end

  FoodTruckType = GenQL::ObjectType.new('FoodTruck', description: 'A food truck stall at an orchard') do
    field :id,                   GenQL::IDType,     description: 'Unique identifier'
    field :orchard_id,           GenQL::IDType,     description: 'Host orchard id'
    field :name,                 GenQL::StringType, description: 'Food truck name'
    field :specialty_variety_id, GenQL::IDType,     description: 'Featured apple variety id'
    field :menu,                 GenQL::StringType, description: 'What the stall serves'
    field :notes,                GenQL::StringType, description: 'Optional stall notes'

    field :orchard, OrchardType, description: 'Orchard hosting this food truck' do |food_truck, _args, _ctx|
      food_truck.orchard
    end

    field :specialty_variety, VarietyType, description: 'Featured apple variety' do |food_truck, _args, _ctx|
      food_truck.specialty_variety
    end
  end

  # Backfill the node type now that FoodTruckType is defined.
  FoodTrucksInOrchardConnection.fields['nodes'].instance_variable_set(:@type, FoodTruckType)

  # ---------------------------------------------------------------------------
  # Connection types — wrap list fields with pagination metadata
  # ---------------------------------------------------------------------------

  # Reusable PageInfo resolver (delegates to the PageResult struct fields).
  PAGE_INFO_RESOLVER = lambda do |page_result, _args, _ctx|
    page_result
  end

  # Top-level connection types
  # ---------------------------------------------------------------------------

  OrchardsConnection  = GenQL.connection_type('OrchardsConnection',  OrchardType,
                                              description: 'Paginated list of orchards')
  VarietiesConnection = GenQL.connection_type('VarietiesConnection', VarietyType,
                                              description: 'Paginated list of varieties')
  HarvestsConnection  = GenQL.connection_type('HarvestsConnection',  HarvestType,
                                              description: 'Paginated list of harvests')
  FoodTrucksConnection = GenQL.connection_type('FoodTrucksConnection', FoodTruckType,
                                               description: 'Paginated list of food trucks')

  # ---------------------------------------------------------------------------
  # Root query type
  # ---------------------------------------------------------------------------

  QueryType = GenQL::ObjectType.new('Query') do
    field :orchards, OrchardsConnection,
          description: 'Paginated list of all orchards' do |_parent, args, _ctx|
      GenQL::Paginator.paginate(Store.orchards,
                                first: args['first'],
                                offset: args['offset'] || 0)
    end

    field :orchard, OrchardType, description: 'Fetch a single orchard by id' do |_parent, args, _ctx|
      Store.orchards.find { |o| o.id == args['id'] }
    end

    field :varieties, VarietiesConnection,
          description: 'Paginated list of all varieties' do |_parent, args, _ctx|
      GenQL::Paginator.paginate(Store.varieties,
                                first: args['first'],
                                offset: args['offset'] || 0)
    end

    field :variety, VarietyType, description: 'Fetch a single variety by id' do |_parent, args, _ctx|
      Store.varieties.find { |v| v.id == args['id'] }
    end

    field :harvests, HarvestsConnection,
          description: 'Paginated list of all harvests' do |_parent, args, _ctx|
      GenQL::Paginator.paginate(Store.harvests,
                                first: args['first'],
                                offset: args['offset'] || 0)
    end

    field :foodTrucks, FoodTrucksConnection,
          description: 'Paginated list of all food trucks' do |_parent, args, _ctx|
      GenQL::Paginator.paginate(Store.food_trucks,
                                first: args['first'],
                                offset: args['offset'] || 0)
    end

    field :foodTruck, FoodTruckType, description: 'Fetch a single food truck by id' do |_parent, args, _ctx|
      Store.food_trucks.find { |ft| ft.id == args['id'] }
    end
  end

  # ---------------------------------------------------------------------------
  # Root mutation type
  # ---------------------------------------------------------------------------

  MutationType = GenQL::ObjectType.new('Mutation') do
    field :addHarvest, HarvestType, description: 'Record a new harvest' do |_parent, args, _ctx|
      harvest = Store.add_harvest(
        orchard_id: args['orchard_id'],
        variety_id: args['variety_id'],
        quantity_kg: args['quantity_kg'].to_i,
        harvested_at: args['harvested_at'],
        notes: args['notes']
      )
      GenQL::SubscriptionBroker.publish('harvestAdded', harvest)
      harvest
    end

    field :addFoodTruck, FoodTruckType, description: 'Open a new food truck stall' do |_parent, args, _ctx|
      food_truck = Store.add_food_truck(
        orchard_id: args['orchard_id'],
        name: args['name'],
        specialty_variety_id: args['specialty_variety_id'],
        menu: args['menu'],
        notes: args['notes']
      )
      GenQL::SubscriptionBroker.publish('foodTruckAdded', food_truck)
      food_truck
    end
  end

  # ---------------------------------------------------------------------------
  # Root subscription type
  # ---------------------------------------------------------------------------

  SubscriptionType = GenQL::ObjectType.new('Subscription') do
    field :harvestAdded, HarvestType, description: 'Fired whenever a new harvest is recorded'
    field :foodTruckAdded, FoodTruckType, description: 'Fired whenever a new food truck stall is opened'
  end

  # ---------------------------------------------------------------------------
  # Schema
  # ---------------------------------------------------------------------------

  SCHEMA = GenQL::Schema.new(query: QueryType, mutation: MutationType, subscription: SubscriptionType)
end
