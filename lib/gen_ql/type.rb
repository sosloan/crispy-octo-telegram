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
  # Schema
  # ---------------------------------------------------------------------------

  # Ties together the root query and mutation types.
  class Schema
    attr_reader :query_type, :mutation_type

    def initialize(query:, mutation: nil)
      @query_type    = query
      @mutation_type = mutation
    end
  end
end
