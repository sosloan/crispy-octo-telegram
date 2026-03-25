# frozen_string_literal: true

require_relative 'ast'
require_relative 'lexer'
require_relative 'parser'
require_relative 'type'

module GenQL
  # Executes a GenQL query string against a Schema and returns a Hash with
  # shape +{ data: {...}, errors: [...] }+.
  #
  # Responsibilities
  #   • Parse the query document.
  #   • Walk the selection set, resolving each field via its FieldDefinition
  #     resolver block, or by calling the matching method / hash key on the
  #     parent object.
  #   • Recurse into sub-selections when the resolved value is an object or an
  #     array of objects.
  #   • Collect field-level errors without aborting the whole execution.
  class Executor
    def initialize(schema)
      @schema = schema
    end

    # @param query_string [String]  GenQL document
    # @param variables    [Hash]    named variable bindings (future extension)
    # @param context      [Hash]    caller-supplied context forwarded to resolvers
    # @return [Hash]  { data: Hash, errors: Array } (errors key omitted when empty)
    def execute(query_string, variables: {}, context: {}) # rubocop:disable Lint/UnusedMethodArgument
      tokens   = Lexer.new(query_string).tokenize
      document = Parser.new(tokens).parse

      data, errors = execute_document(document, context)

      response = { data: data }
      response[:errors] = errors unless errors.empty?
      response
    end

    private

    def execute_document(document, context)
      data   = {}
      errors = []
      document.operations.each do |operation|
        root_type = root_type_for(operation.type)
        unless root_type
          errors << { message: "No #{operation.type} type defined in schema" }
          next
        end

        begin
          data.merge!(resolve_selections(operation.selections, root_type, nil, context))
        rescue ExecutionError => e
          errors << { message: e.message }
        end
      end
      [data, errors]
    end

    def root_type_for(op_type)
      case op_type
      when :query, 'query'        then @schema.query_type
      when :mutation, 'mutation'  then @schema.mutation_type
      end
    end

    # Resolve a list of AST::Field selections against *type*, where
    # *parent_object* is the resolved value of the enclosing field.
    def resolve_selections(selections, type, parent_object, context)
      selections.each_with_object({}) do |ast_field, result|
        field_def = type.fields[ast_field.name]
        unless field_def
          raise ExecutionError,
                "Field '#{ast_field.name}' not found on type '#{type.name}'"
        end

        resolved = call_resolver(field_def, parent_object, ast_field.arguments, context)

        result[ast_field.name] = if ast_field.selections.any?
                                   resolve_nested(resolved, ast_field, field_def, context)
                                 else
                                   resolved
                                 end
      end
    end

    def call_resolver(field_def, parent_object, arguments, context)
      if field_def.resolver
        field_def.resolver.call(parent_object, arguments, context)
      elsif parent_object.respond_to?(field_def.name)
        parent_object.public_send(field_def.name)
      elsif parent_object.is_a?(Hash)
        parent_object[field_def.name] || parent_object[field_def.name.to_sym]
      end
    end

    def resolve_nested(resolved, ast_field, field_def, context)
      child_type = field_def.type
      if resolved.is_a?(Array)
        resolved.map { |item| resolve_selections(ast_field.selections, child_type, item, context) }
      elsif resolved.nil?
        nil
      else
        resolve_selections(ast_field.selections, child_type, resolved, context)
      end
    end
  end

  class ExecutionError < StandardError
  end
end
