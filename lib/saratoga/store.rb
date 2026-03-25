# frozen_string_literal: true

require_relative 'database'

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
  # ---------------------------------------------------------------------------
  module Store
    class << self
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
      end
    end
  end
end
