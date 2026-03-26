# frozen_string_literal: true

module GenQL
  # ---------------------------------------------------------------------------
  # Scalar types
  # ---------------------------------------------------------------------------

  # Marker module for scalar types (String, Int, Float, Boolean, ID).
  module Scalar; end

  StringType = Object.new.tap do |o|
    o.define_singleton_method(:name) { 'String' }
    o.extend(Scalar)
  end
  IntType = Object.new.tap do |o|
    o.define_singleton_method(:name) { 'Int' }
    o.extend(Scalar)
  end
  FloatType = Object.new.tap do |o|
    o.define_singleton_method(:name) { 'Float' }
    o.extend(Scalar)
  end
  BooleanType = Object.new.tap do |o|
    o.define_singleton_method(:name) { 'Boolean' }
    o.extend(Scalar)
  end
  IDType = Object.new.tap do |o|
    o.define_singleton_method(:name) { 'ID' }
    o.extend(Scalar)
  end

  # ---------------------------------------------------------------------------
  # Field definition
  # ---------------------------------------------------------------------------

  # Holds metadata for a single field inside an ObjectType.
  # The optional +resolver+ block has the signature:
  #   (parent_object, arguments, context) -> value
  class FieldDefinition
    attr_reader :name, :type, :description, :resolver

    def initialize(name, type, description: nil, &resolver)
      @name        = name.to_s
      @type        = type
      @description = description
      @resolver    = resolver
    end
  end

  # ---------------------------------------------------------------------------
  # Object type
  # ---------------------------------------------------------------------------

  # Represents a named object type with a set of FieldDefinitions.
  #
  # Usage:
  #   OrchardType = GenQL::ObjectType.new("Orchard") do
  #     field :id,   GenQL::IDType
  #     field :name, GenQL::StringType
  #   end
  class ObjectType
    attr_reader :name, :description, :fields

    def initialize(name, description: nil, &block)
      @name        = name.to_s
      @description = description
      @fields      = {}
      instance_eval(&block) if block
    end

    # DSL method called inside the constructor block.
    def field(name, type, description: nil, &resolver)
      key = name.to_s
      @fields[key] = FieldDefinition.new(key, type, description: description, &resolver)
    end
  end

  # ---------------------------------------------------------------------------
  # Built-in connection support types
  # ---------------------------------------------------------------------------

  # Describes the pagination state for a connection field.
  # Returned as the +page_info+ sub-field on every *Connection type.
  PageInfoType = ObjectType.new('PageInfo', description: 'Pagination metadata for a connection') do
    field :has_next_page, BooleanType, description: 'Whether more items exist after this page'
    field :start_cursor,  StringType,  description: 'Cursor of the first item on this page'
    field :end_cursor,    StringType,  description: 'Cursor of the last item on this page; ' \
                                                    'pass as `after` to fetch the next page'
  # Pagination types
  # ---------------------------------------------------------------------------

  # ObjectType that describes the metadata returned alongside a paginated list.
  # Fields are resolved directly from a +GenQL::PageResult+ instance.
  PageInfoType = ObjectType.new('PageInfo', description: 'Pagination metadata for a connection') do
    field :total_count,       IntType,     description: 'Total number of items in the unpaginated collection'
    field :has_next_page,     BooleanType, description: 'Whether more items follow the current page'
    field :has_previous_page, BooleanType, description: 'Whether items precede the current page'
  end

  # Factory that produces a named connection ObjectType wrapping *node_type*.
  #
  # The returned type exposes two fields:
  #   nodes     – the paginated array of *node_type* objects
  #   page_info – a +PageInfoType+ object with total_count and page flags
  #
  # Both fields resolve from a +GenQL::PageResult+ value returned by the
  # resolver of the corresponding list field.
  #
  # Usage:
  #   OrchardsConnection = GenQL.connection_type('OrchardsConnection', OrchardType)
  def self.connection_type(name, node_type, description: nil)
    ObjectType.new(name, description: description) do
      field :nodes,     node_type,    description: 'Paginated list of items' do |result, _args, _ctx|
        result.nodes
      end
      field :page_info, PageInfoType, description: 'Pagination metadata' do |result, _args, _ctx|
        result
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Schema
  # ---------------------------------------------------------------------------

  # Ties together the root query, mutation, and subscription types.
  class Schema
    attr_reader :query_type, :mutation_type, :subscription_type

    def initialize(query:, mutation: nil, subscription: nil)
      @query_type        = query
      @mutation_type     = mutation
      @subscription_type = subscription
    end
  end
end
