# frozen_string_literal: true

require_relative 'database'
require_relative 'persistence'

module Saratoga
  # ---------------------------------------------------------------------------
  # Value objects for the Saratoga Orchards domain.
  # ---------------------------------------------------------------------------

  Variety = Struct.new(:id, :name, :species, :season, :notes)

  Orchard = Struct.new(:id, :name, :location, :established_year, :variety_ids) do
    def varieties
      Store.varieties.select { |v| variety_ids.include?(v.id) }
    end
  end

  Harvest = Struct.new(:id, :orchard_id, :variety_id, :quantity_kg,
                       :harvested_at, :notes) do
    def orchard
      Store.orchards.find { |o| o.id == orchard_id }
    end

    def variety
      Store.varieties.find { |v| v.id == variety_id }
    end
  end

  # ---------------------------------------------------------------------------
  # Store — SQLite-backed repository for the Saratoga domain.
  #
  # All public methods return domain value objects (Variety, Orchard, Harvest)
  # so the GenQL schema resolvers and the rest of the application are
  # unaffected by the change from in-memory arrays to a real database.
  # In-memory data store with seed data and optional JSON persistence.
  #
  # Set +Store.data_file=+ (or the +SARATOGA_DATA_FILE+ environment variable)
  # to a writable path before the first access to enable persistence.  When
  # persistence is enabled:
  #   • harvests are loaded from the file on first access
  #   • every +add_harvest+ call flushes the updated list back to the file
  #   • +reset!+ removes the file so the next boot starts from seed data
  # ---------------------------------------------------------------------------
  module Store
    class << self
      attr_accessor :data_file

      def varieties
        db.execute('SELECT id, name, species, season, notes FROM varieties ORDER BY id').map do |row|
          Variety.new(id: row['id'], name: row['name'], species: row['species'],
                      season: row['season'], notes: row['notes'])
        end
      end

      def orchards
        db.execute('SELECT id, name, location, established_year FROM orchards ORDER BY id').map do |row|
          variety_ids = db.execute(
            'SELECT variety_id FROM orchard_varieties WHERE orchard_id = ? ORDER BY variety_id',
            [row['id']]
          ).map { |r| r['variety_id'] }

          Orchard.new(id: row['id'], name: row['name'], location: row['location'],
                      established_year: row['established_year'], variety_ids: variety_ids)
        end
      end

      def harvests
        db.execute(
          'SELECT id, orchard_id, variety_id, quantity_kg, harvested_at, notes FROM harvests ORDER BY id'
        ).map { |row| harvest_from_row(row) }
        @harvests ||= Persistence.load(data_file) || [
          Harvest.new(id: 'h1', orchard_id: 'o1', variety_id: 'v1',
                      quantity_kg: 1_240, harvested_at: '2023-08-12',
                      notes: 'Excellent crop; minimal pest pressure'),
          Harvest.new(id: 'h2', orchard_id: 'o1', variety_id: 'v2',
                      quantity_kg: 980,   harvested_at: '2023-10-05', notes: nil),
          Harvest.new(id: 'h3', orchard_id: 'o2', variety_id: 'v4',
                      quantity_kg: 560,   harvested_at: '2023-09-18', notes: nil),
          Harvest.new(id: 'h4', orchard_id: 'o3', variety_id: 'v1',
                      quantity_kg: 430,   harvested_at: '2023-08-20', notes: nil)
        ]
      end

      # Mutation helpers --------------------------------------------------

      def add_harvest(orchard_id:, variety_id:, quantity_kg:, harvested_at:, notes: nil)
        next_id = next_harvest_id
        db.execute(
          'INSERT INTO harvests (id, orchard_id, variety_id, quantity_kg, harvested_at, notes) ' \
          'VALUES (?, ?, ?, ?, ?, ?)',
          [next_id, orchard_id, variety_id, quantity_kg, harvested_at, notes]
        )
        Harvest.new(id: next_id, orchard_id: orchard_id, variety_id: variety_id,
                    quantity_kg: quantity_kg, harvested_at: harvested_at, notes: notes)
        @next_harvest_id += 1
        harvests << harvest
        Persistence.save(data_file, harvests)
        harvest
      end

      # Reset the database to a clean seeded state (used for test isolation).
      def reset!
        Database.reset!
      end

      private

      def db
        Database.connection
      end

      def next_harvest_id
        max_row = db.execute('SELECT MAX(CAST(SUBSTR(id, 2) AS INTEGER)) AS max_n FROM harvests').first
        n = (max_row && max_row['max_n'] ? max_row['max_n'] : 0) + 1
        "h#{n}"
      end

      def harvest_from_row(row)
        Harvest.new(
          id: row['id'],
          orchard_id: row['orchard_id'],
          variety_id: row['variety_id'],
          quantity_kg: row['quantity_kg'],
          harvested_at: row['harvested_at'],
          notes: row['notes']
        )
        Persistence.delete(data_file)
        @varieties       = nil
        @orchards        = nil
        @harvests        = nil
        @next_harvest_id = nil
      end
    end
  end
end
