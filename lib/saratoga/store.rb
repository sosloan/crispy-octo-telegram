# frozen_string_literal: true

module Saratoga
  # Simple value objects for the Saratoga Orchards domain.
  # In a production system these would be backed by a database.

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
  # In-memory data store with seed data
  # ---------------------------------------------------------------------------
  module Store
    class << self
      def varieties
        @varieties ||= [
          Variety.new(id: 'v1', name: 'Gravenstein', species: 'Malus domestica',
                      season: 'early',  notes: 'Tart and aromatic; Saratoga heritage variety'),
          Variety.new(id: 'v2', name: 'Pippin', species: 'Malus domestica',
                      season: 'late',   notes: 'Crisp with a spiced finish'),
          Variety.new(id: 'v3', name: 'Roxbury Russet', species: 'Malus domestica',
                      season: 'late',   notes: 'American heirloom; excellent for cider'),
          Variety.new(id: 'v4', name: 'Calville Blanc', species: 'Malus domestica',
                      season: 'mid',    notes: 'French heirloom; high vitamin C'),
          Variety.new(id: 'v5', name: 'Wealthy',        species: 'Malus domestica',
                      season: 'mid',    notes: 'Hardy mid-season variety')
        ]
      end

      def orchards
        @orchards ||= [
          Orchard.new(id: 'o1', name: 'Saratoga Hill Block',
                      location: 'Saratoga, CA', established_year: 1952,
                      variety_ids: %w[v1 v2 v3]),
          Orchard.new(id: 'o2', name: 'Summit Ridge',
                      location: 'Los Gatos, CA', established_year: 1978,
                      variety_ids: %w[v2 v4 v5]),
          Orchard.new(id: 'o3', name: 'Creekside Block',
                      location: 'Saratoga, CA', established_year: 2003,
                      variety_ids: %w[v1 v5])
        ]
      end

      def harvests
        @harvests ||= [
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
        harvest = Harvest.new(
          id: "h#{harvests.length + 1}",
          orchard_id: orchard_id,
          variety_id: variety_id,
          quantity_kg: quantity_kg,
          harvested_at: harvested_at,
          notes: notes
        )
        harvests << harvest
        harvest
      end

      def reset!
        @varieties = nil
        @orchards  = nil
        @harvests  = nil
      end
    end
  end
end
