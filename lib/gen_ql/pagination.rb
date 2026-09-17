# frozen_string_literal: true

module GenQL
  PageResult = Struct.new(
    :nodes,
    :total_count,
    :has_next_page,
    :has_previous_page,
    :start_cursor,
    :end_cursor
  )

  # Stateless pagination for ordered collections. Both offset pagination and
  # opaque, id-based cursors are supported for backwards compatibility.
  module Paginator
    def self.paginate(collection, first: nil, offset: 0, after: nil)
      start = after ? cursor_offset(collection, after) : [(offset || 0).to_i, 0].max
      total = collection.length
      limit = first.nil? ? total : [first.to_i, 0].max
      nodes = collection.slice(start, limit) || []

      PageResult.new(
        nodes,
        total,
        start + nodes.length < total,
        start.positive?,
        nodes.empty? ? nil : cursor_for(nodes.first),
        nodes.empty? ? nil : cursor_for(nodes.last)
      )
    end

    def self.cursor_for(item)
      item.respond_to?(:id) ? item.id.to_s : item.object_id.to_s
    end

    def self.cursor_offset(collection, after)
      index = collection.index { |item| cursor_for(item) == after.to_s }
      index ? index + 1 : collection.length
    end
    private_class_method :cursor_offset
  end

  Pagination = Paginator
end
