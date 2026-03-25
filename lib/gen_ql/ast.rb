# frozen_string_literal: true

module GenQL
  # Abstract Syntax Tree nodes produced by the GenQL parser.
  #
  # Each operation has a type (:query or :mutation), an optional name, and a
  # list of field selections.  Selections are nested recursively so that
  # sub-selection sets are modelled by the +selections+ attribute of a Field.
  module AST
    Document  = Struct.new(:operations)
    Operation = Struct.new(:type, :name, :selections)
    Field     = Struct.new(:name, :arguments, :selections)
  end
end
