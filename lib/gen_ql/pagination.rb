# frozen_string_literal: true

module GenQL
  # Holds the result of a paginated query: the sliced +nodes+, the
  # +total_count+ of the full collection, and boolean flags for whether
  # additional pages exist before or after the current window.
  PageResult = Struct.new(:nodes, :total_count, :has_next_page, :has_previous_page)

  # Stateless helper that slices a plain Ruby Array (or any object that
  # responds to +length+ and +slice+) according to +first+ / +offset+
  # pagination arguments.
  #
  # Usage:
  #   result = GenQL::Paginator.paginate(Store.orchards, first: 2, offset: 0)
  #   result.nodes          #=> first 2 items
  #   result.total_count    #=> total number of items
  #   result.has_next_page  #=> true if more items follow
  module Paginator
    # @param collection [Array]        The full, unpaginated collection.
    # @param first      [Integer, nil] Maximum number of items to return.
    #                                  +nil+ means return all remaining items.
    # @param offset     [Integer]      Zero-based index of the first item to
    #                                  include (default: 0).
    # @return [PageResult]
    def self.paginate(collection, first: nil, offset: 0)
      offset = offset.to_i
      total  = collection.length

      nodes = if first
                collection.slice(offset, first.to_i) || []
              else
                collection[offset..] || []
              end

      has_next = (offset + nodes.length) < total
      has_prev = offset > 0

      PageResult.new(nodes, total, has_next, has_prev)
    end
  end
end
