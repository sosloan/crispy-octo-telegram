# frozen_string_literal: true

require 'sqlite3'

module Saratoga
  # ---------------------------------------------------------------------------
  # Database — SQLite connection, schema migrations, and seed data.
  #
  # Uses an in-memory database when SARATOGA_ENV is "test" (or when an
  # explicit URI is not provided) so the test suite never touches the
  # filesystem and always starts from a clean slate.
  #
  # Production and development use a file-based database whose path is
  # controlled by the SARATOGA_DATABASE_PATH environment variable
  # (default: "saratoga.db" in the working directory).
  # ---------------------------------------------------------------------------
  module Database
    DB_PATH_ENV = 'SARATOGA_DATABASE_PATH'
    TEST_ENV    = 'test'

    SEED_VARIETIES = [
      { id: 'v1', name: 'Gravenstein',    species: 'Malus domestica',
        season: 'early', notes: 'Tart and aromatic; Saratoga heritage variety' },
      { id: 'v2', name: 'Pippin',         species: 'Malus domestica',
        season: 'late',  notes: 'Crisp with a spiced finish' },
      { id: 'v3', name: 'Roxbury Russet', species: 'Malus domestica',
        season: 'late',  notes: 'American heirloom; excellent for cider' },
      { id: 'v4', name: 'Calville Blanc', species: 'Malus domestica',
        season: 'mid',   notes: 'French heirloom; high vitamin C' },
      { id: 'v5', name: 'Wealthy',        species: 'Malus domestica',
        season: 'mid',   notes: 'Hardy mid-season variety' }
    ].freeze

    SEED_ORCHARDS = [
      { id: 'o1', name: 'Saratoga Hill Block', location: 'Saratoga, CA',  established_year: 1952,
        variety_ids: %w[v1 v2 v3] },
      { id: 'o2', name: 'Summit Ridge',        location: 'Los Gatos, CA', established_year: 1978,
        variety_ids: %w[v2 v4 v5] },
      { id: 'o3', name: 'Creekside Block',     location: 'Saratoga, CA',  established_year: 2003,
        variety_ids: %w[v1 v5] }
    ].freeze

    SEED_HARVESTS = [
      { id: 'h1', orchard_id: 'o1', variety_id: 'v1', quantity_kg: 1_240,
        harvested_at: '2023-08-12', notes: 'Excellent crop; minimal pest pressure' },
      { id: 'h2', orchard_id: 'o1', variety_id: 'v2', quantity_kg: 980,
        harvested_at: '2023-10-05', notes: nil },
      { id: 'h3', orchard_id: 'o2', variety_id: 'v4', quantity_kg: 560,
        harvested_at: '2023-09-18', notes: nil },
      { id: 'h4', orchard_id: 'o3', variety_id: 'v1', quantity_kg: 430,
        harvested_at: '2023-08-20', notes: nil }
    ].freeze

    class << self
      # Returns the shared SQLite3::Database connection, creating it on first
      # call.  Thread-safety is acceptable here because SQLite serialises all
      # writes and the connection is shared read-only after setup.
      def connection
        @connection ||= open_and_setup
      end

      # Replaces the current connection with a brand-new one.  All in-memory
      # state is discarded and the schema + seed data are re-applied.
      # Intended for test isolation (Store.reset! delegates here).
      def reset!
        begin
          @connection&.close
        rescue SQLite3::Exception
          # Ignore errors from closing an already-closed connection
        end
        @connection = open_and_setup
      end

      private

      def test_env?
        ENV.fetch('SARATOGA_ENV', '').strip.downcase == TEST_ENV
      end

      def db_uri
        test_env? ? ':memory:' : ENV.fetch(DB_PATH_ENV, 'saratoga.db')
      end

      def open_and_setup
        db = SQLite3::Database.new(db_uri)
        db.results_as_hash = true
        db.execute('PRAGMA foreign_keys = ON')
        create_schema(db)
        seed(db)
        db
      end

      # ------------------------------------------------------------------
      # DDL — one method per table for readability
      # ------------------------------------------------------------------

      def create_schema(db)
        create_varieties_table(db)
        create_orchards_table(db)
        create_orchard_varieties_table(db)
        create_harvests_table(db)
      end

      def create_varieties_table(db)
        db.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS varieties (
            id      TEXT PRIMARY KEY,
            name    TEXT NOT NULL,
            species TEXT NOT NULL,
            season  TEXT NOT NULL,
            notes   TEXT
          )
        SQL
      end

      def create_orchards_table(db)
        db.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS orchards (
            id               TEXT PRIMARY KEY,
            name             TEXT NOT NULL,
            location         TEXT NOT NULL,
            established_year INTEGER NOT NULL
          )
        SQL
      end

      def create_orchard_varieties_table(db)
        db.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS orchard_varieties (
            orchard_id  TEXT NOT NULL REFERENCES orchards(id),
            variety_id  TEXT NOT NULL REFERENCES varieties(id),
            PRIMARY KEY (orchard_id, variety_id)
          )
        SQL
      end

      def create_harvests_table(db)
        db.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS harvests (
            id           TEXT PRIMARY KEY,
            orchard_id   TEXT NOT NULL REFERENCES orchards(id),
            variety_id   TEXT NOT NULL REFERENCES varieties(id),
            quantity_kg  INTEGER NOT NULL,
            harvested_at TEXT NOT NULL,
            notes        TEXT
          )
        SQL
      end

      # ------------------------------------------------------------------
      # Seed data (mirrors the original in-memory fixtures)
      # ------------------------------------------------------------------

      def seed(db)
        seed_varieties(db)
        seed_orchards(db)
        seed_harvests(db)
      end

      def seed_varieties(db)
        SEED_VARIETIES.each do |v|
          db.execute(
            'INSERT OR IGNORE INTO varieties (id, name, species, season, notes) VALUES (?, ?, ?, ?, ?)',
            [v[:id], v[:name], v[:species], v[:season], v[:notes]]
          )
        end
      end

      def seed_orchards(db)
        SEED_ORCHARDS.each do |o|
          db.execute(
            'INSERT OR IGNORE INTO orchards (id, name, location, established_year) VALUES (?, ?, ?, ?)',
            [o[:id], o[:name], o[:location], o[:established_year]]
          )
          o[:variety_ids].each do |vid|
            db.execute(
              'INSERT OR IGNORE INTO orchard_varieties (orchard_id, variety_id) VALUES (?, ?)',
              [o[:id], vid]
            )
          end
        end
      end

      def seed_harvests(db)
        SEED_HARVESTS.each do |h|
          db.execute(
            'INSERT OR IGNORE INTO harvests (id, orchard_id, variety_id, quantity_kg, harvested_at, notes) ' \
            'VALUES (?, ?, ?, ?, ?, ?)',
            [h[:id], h[:orchard_id], h[:variety_id], h[:quantity_kg], h[:harvested_at], h[:notes]]
          )
        end
      end
    end
  end
end
