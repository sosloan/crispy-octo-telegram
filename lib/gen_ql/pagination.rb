# frozen_string_literal: true

module GenQL
  # Cursor-based pagination helper for in-memory item lists.
  #
  # A cursor is the +id+ string of the last item seen by the client.  The
  # client passes it back as the +after+ argument to retrieve the next page.
  #
  # Usage:
  #   result = Pagination.paginate(Store.orchards, first: 2, after: "o1")
  #   result.nodes         # => [<Orchard o2>, <Orchard o3>]
  #   result.has_next_page # => false
  #   result.end_cursor    # => "o3"
  module Pagination
    # Value object returned by +paginate+.
    PageResult = Struct.new(:nodes, :has_next_page, :end_cursor, :start_cursor)

    # @param items  [Array]        full ordered list of domain objects
    # @param first  [Integer, nil] maximum number of items to return; nil returns all
    # @param after  [String, nil]  opaque cursor (item id) after which to start
    # @return [PageResult]
    def self.paginate(items, first: nil, after: nil)
      sliced           = items[start_index(items, after)..] || []
      nodes, has_next  = apply_limit(sliced, first)

      PageResult.new(
        nodes: nodes,
        has_next_page: has_next,
        end_cursor: nodes.empty? ? nil : cursor_for(nodes.last),
        start_cursor: nodes.empty? ? nil : cursor_for(nodes.first)
      )
    end

    # Returns the opaque cursor string for a single item.
    def self.cursor_for(item)
      item.respond_to?(:id) ? item.id.to_s : item.object_id.to_s
    end

    # @api private
    def self.start_index(items, after)
      return 0 unless after

      idx = items.index { |i| cursor_for(i) == after.to_s }
      # Unknown / stale cursor → return items.length so the slice is empty,
      # signalling to the client that the cursor is no longer valid.
      idx ? idx + 1 : items.length
    end

    # @api private
    def self.apply_limit(sliced, first)
      return [sliced, false] unless first

      limit = first.to_i
      [sliced.first(limit), sliced.length > limit]
    end
  end
end
