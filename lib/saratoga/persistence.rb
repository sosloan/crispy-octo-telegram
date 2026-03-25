# frozen_string_literal: true

require 'json'
require 'fileutils'

module Saratoga
  # Handles reading and writing store state to a JSON file so that mutations
  # survive server restarts (offline / no-external-database operation).
  #
  # Only *dynamic* data (harvests added via mutations) is persisted; the
  # seed varieties and orchards are always reconstituted from the in-memory
  # defaults because they are static reference data.
  module Persistence
    # Load persisted harvests from *path*.
    #
    # @param path [String, nil] absolute or relative path to the JSON file.
    #   Pass +nil+ to skip loading (useful in tests).
    # @return [Array<Harvest>, nil]  array of Harvest objects, or +nil+ when
    #   the file does not exist or *path* is +nil+.
    def self.load(path)
      return nil unless path && File.exist?(path)

      data = JSON.parse(File.read(path), symbolize_names: true)
      Array(data[:harvests]).map do |h|
        Harvest.new(
          id: h[:id],
          orchard_id: h[:orchard_id],
          variety_id: h[:variety_id],
          quantity_kg: h[:quantity_kg],
          harvested_at: h[:harvested_at],
          notes: h[:notes]
        )
      end
    rescue JSON::ParserError
      nil
    end

    # Persist the current list of harvests to *path*.
    #
    # @param path     [String, nil]    target file path; no-op when +nil+.
    # @param harvests [Array<Harvest>] harvests to serialise.
    def self.save(path, harvests)
      return unless path

      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.generate(harvests: harvests.map(&:to_h)))
    end

    # Delete the persisted data file.
    #
    # @param path [String, nil] file to remove; no-op when +nil+ or absent.
    def self.delete(path)
      File.delete(path) if path && File.exist?(path)
    end
  end
end
