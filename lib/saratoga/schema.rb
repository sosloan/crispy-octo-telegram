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

  OrchardType = GenQL::ObjectType.new('Orchard', description: 'A named orchard block') do
    field :id,               GenQL::IDType,     description: 'Unique identifier'
    field :name,             GenQL::StringType, description: 'Orchard block name'
    field :location,         GenQL::StringType, description: 'Geographic location'
    field :established_year, GenQL::IntType,    description: 'Year the block was planted'

    field :varieties, VarietyType, description: 'Apple varieties grown in this orchard' do |orchard, _args, _ctx|
      orchard.varieties
    end

    field :harvests, HarvestType, description: 'All harvests recorded for this orchard' do |orchard, _args, _ctx|
      Store.harvests.select { |h| h.orchard_id == orchard.id }
    end
  end

  # ---------------------------------------------------------------------------
  # Connection types — wrap list fields with pagination metadata
  # ---------------------------------------------------------------------------

  # Reusable PageInfo resolver (delegates to the PageResult struct fields).
  PAGE_INFO_RESOLVER = lambda do |page_result, _args, _ctx|
    page_result
  end

  OrchardConnection = GenQL::ObjectType.new('OrchardConnection',
                                            description: 'Paginated list of orchards') do
    field :nodes, OrchardType, description: 'Orchards on this page' do |conn, _args, _ctx|
      conn.nodes
    end

    field :page_info, GenQL::PageInfoType, description: 'Pagination metadata', &PAGE_INFO_RESOLVER
  end

  VarietyConnection = GenQL::ObjectType.new('VarietyConnection',
                                            description: 'Paginated list of varieties') do
    field :nodes, VarietyType, description: 'Varieties on this page' do |conn, _args, _ctx|
      conn.nodes
    end

    field :page_info, GenQL::PageInfoType, description: 'Pagination metadata', &PAGE_INFO_RESOLVER
  end

  HarvestConnection = GenQL::ObjectType.new('HarvestConnection',
                                            description: 'Paginated list of harvests') do
    field :nodes, HarvestType, description: 'Harvests on this page' do |conn, _args, _ctx|
      conn.nodes
    end

    field :page_info, GenQL::PageInfoType, description: 'Pagination metadata', &PAGE_INFO_RESOLVER
  end

  # ---------------------------------------------------------------------------
  # Root query type
  # ---------------------------------------------------------------------------

  QueryType = GenQL::ObjectType.new('Query') do
    field :orchards, OrchardConnection,
          description: 'Paginated orchard list; use `first` and `after` for infinite scroll' do |_parent, args, _ctx|
      GenQL::Pagination.paginate(Store.orchards,
                                 first: args['first'],
                                 after: args['after'])
    end

    field :orchard, OrchardType, description: 'Fetch a single orchard by id' do |_parent, args, _ctx|
      Store.orchards.find { |o| o.id == args['id'] }
    end

    field :varieties, VarietyConnection,
          description: 'Paginated variety list; use `first` and `after` for infinite scroll' do |_parent, args, _ctx|
      GenQL::Pagination.paginate(Store.varieties,
                                 first: args['first'],
                                 after: args['after'])
    end

    field :variety, VarietyType, description: 'Fetch a single variety by id' do |_parent, args, _ctx|
      Store.varieties.find { |v| v.id == args['id'] }
    end

    field :harvests, HarvestConnection,
          description: 'Paginated harvest list; use `first` and `after` for infinite scroll' do |_parent, args, _ctx|
      GenQL::Pagination.paginate(Store.harvests,
                                 first: args['first'],
                                 after: args['after'])
    end
  end

  # ---------------------------------------------------------------------------
  # Root mutation type
  # ---------------------------------------------------------------------------

  MutationType = GenQL::ObjectType.new('Mutation') do
    field :addHarvest, HarvestType, description: 'Record a new harvest' do |_parent, args, _ctx|
      Store.add_harvest(
        orchard_id: args['orchard_id'],
        variety_id: args['variety_id'],
        quantity_kg: args['quantity_kg'].to_i,
        harvested_at: args['harvested_at'],
        notes: args['notes']
      )
    end
  end

  # ---------------------------------------------------------------------------
  # Schema
  # ---------------------------------------------------------------------------

  SCHEMA = GenQL::Schema.new(query: QueryType, mutation: MutationType)
end
