# frozen_string_literal: true

require_relative 'ast'

module GenQL
  # Recursive-descent parser that converts a flat Token stream into an AST.
  #
  # Grammar (simplified):
  #   document      →  operation+
  #   operation     →  ("query"|"mutation") name? "{" selection_set "}"
  #                 |  "{" selection_set "}"
  #   selection_set →  field*
  #   field         →  NAME arguments? ("{" selection_set "}")?
  #   arguments     →  "(" (argument ","?)* ")"
  #   argument      →  NAME ":" value
  #   value         →  STRING | INT | FLOAT | TRUE | FALSE | NULL | NAME
  class Parser
    OP_TOKENS    = %i[QUERY MUTATION SUBSCRIPTION].freeze
    VALUE_TOKENS = %i[STRING INT FLOAT TRUE FALSE NULL NAME].freeze

    def initialize(tokens)
      @tokens = tokens
      @pos    = 0
    end

    # Returns a +GenQL::AST::Document+.
    def parse
      operations = []
      operations << parse_operation until peek.type == :EOF
      raise ParseError, 'Expected at least one operation' if operations.empty?

      AST::Document.new(operations)
    end

    private

    def parse_operation
      op_type = if OP_TOKENS.include?(peek.type)
                  consume.value.to_sym
                elsif peek.type == :LBRACE
                  :query
                else
                  raise ParseError, "Expected operation keyword or '{', got #{peek.type}"
                end

      name = peek.type == :NAME ? consume.value : nil
      expect(:LBRACE)
      selections = parse_selection_set
      expect(:RBRACE)

      AST::Operation.new(op_type, name, selections)
    end

    def parse_selection_set
      fields = []
      fields << parse_field while peek.type == :NAME
      fields
    end

    def parse_field
      name      = expect(:NAME).value
      arguments = peek.type == :LPAREN ? parse_arguments : {}
      selections = if peek.type == :LBRACE
                     expect(:LBRACE)
                     sel = parse_selection_set
                     expect(:RBRACE)
                     sel
                   else
                     []
                   end
      AST::Field.new(name, arguments, selections)
    end

    def parse_arguments
      args = {}
      expect(:LPAREN)
      until peek.type == :RPAREN
        k = expect(:NAME).value
        expect(:COLON)
        args[k] = parse_value
        consume if peek.type == :COMMA
      end
      expect(:RPAREN)
      args
    end

    def parse_value
      t = peek
      raise ParseError, "Expected a value, got #{t.type}" unless VALUE_TOKENS.include?(t.type)

      consume
      case t.type
      when :TRUE  then true
      when :FALSE then false
      when :NULL  then nil
      else t.value
      end
    end

    def peek
      @tokens[@pos]
    end

    def consume
      token = @tokens[@pos]
      @pos += 1
      token
    end

    def expect(type)
      token = consume
      return token if token.type == type

      raise ParseError,
            "Expected #{type}, got #{token.type} (#{token.value.inspect}) at token #{@pos}"
    end
  end

  class ParseError < StandardError
  end
end
