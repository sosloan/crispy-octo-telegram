# frozen_string_literal: true

# Benchmark the GenQL pipeline: lexer, parser, and executor, using the
# Saratoga Orchards schema as the real-world subject under test.
#
# Run with:
#   bundle exec ruby bench/benchmark.rb
#
# Results are printed to stdout in two passes (rehearsal + real) so that
# garbage-collection pressure from the rehearsal pass does not inflate the
# real measurements.

require 'benchmark'
require_relative '../lib/gen_ql'
require_relative '../lib/saratoga'

# ---------------------------------------------------------------------------
# Queries used across multiple benchmark cases
# ---------------------------------------------------------------------------

QUERIES = {
  simple_scalar: '{ orchards { name } }',

  list_with_scalars: '{ orchards { id name location established_year } }',

  nested_one_level: '{ orchards { name varieties { name season } } }',

  nested_two_levels: <<~GQL,
    {
      orchards {
        name
        location
        varieties { name species season notes }
        harvests  { id quantity_kg harvested_at }
      }
    }
  GQL

  deeply_nested: <<~GQL,
    {
      orchards {
        id
        name
        location
        established_year
        varieties { id name species season notes }
        harvests  { id quantity_kg harvested_at notes variety { id name species } }
      }
    }
  GQL

  single_orchard: '{ orchard(id: "o1") { id name location } }',

  single_orchard_nested: <<~GQL,
    {
      orchard(id: "o2") {
        name
        varieties { name season }
        harvests  { quantity_kg harvested_at variety { name } }
      }
    }
  GQL

  all_varieties: '{ varieties { id name species season notes } }',

  all_harvests: '{ harvests { id orchard_id variety_id quantity_kg harvested_at } }',

  harvests_with_variety: '{ harvests { id quantity_kg harvested_at variety { name species } } }',

  mutation: <<~GQL
    mutation {
      addHarvest(
        orchard_id: "o1",
        variety_id: "v1",
        quantity_kg: 400,
        harvested_at: "2024-10-01"
      ) { id orchard_id variety_id quantity_kg harvested_at }
    }
  GQL
}.freeze

EXECUTOR = GenQL::Executor.new(Saratoga::SCHEMA)

N = 1_000 # iterations per case

# ---------------------------------------------------------------------------
# Helper – build a pre-tokenised token stream for parser-only benchmarks
# ---------------------------------------------------------------------------
def tokens_for(query)
  GenQL::Lexer.new(query).tokenize
end

QUERY_TOKENS = QUERIES.transform_values { |q| tokens_for(q) }.freeze

# ---------------------------------------------------------------------------
# Benchmark suite
# ---------------------------------------------------------------------------

puts "GenQL benchmark  —  #{N} iterations per case\n\n"

Benchmark.bmbm(40) do |x|
  # ── Lexer ──────────────────────────────────────────────────────────────────
  x.report('lexer: simple scalar') do
    N.times { GenQL::Lexer.new(QUERIES[:simple_scalar]).tokenize }
  end

  x.report('lexer: list with scalars') do
    N.times { GenQL::Lexer.new(QUERIES[:list_with_scalars]).tokenize }
  end

  x.report('lexer: nested one level') do
    N.times { GenQL::Lexer.new(QUERIES[:nested_one_level]).tokenize }
  end

  x.report('lexer: deeply nested') do
    N.times { GenQL::Lexer.new(QUERIES[:deeply_nested]).tokenize }
  end

  # ── Parser ─────────────────────────────────────────────────────────────────
  x.report('parser: simple scalar') do
    N.times { GenQL::Parser.new(QUERY_TOKENS[:simple_scalar].dup).parse }
  end

  x.report('parser: list with scalars') do
    N.times { GenQL::Parser.new(QUERY_TOKENS[:list_with_scalars].dup).parse }
  end

  x.report('parser: nested one level') do
    N.times { GenQL::Parser.new(QUERY_TOKENS[:nested_one_level].dup).parse }
  end

  x.report('parser: deeply nested') do
    N.times { GenQL::Parser.new(QUERY_TOKENS[:deeply_nested].dup).parse }
  end

  # ── Executor (full pipeline: lex + parse + execute) ─────────────────────────
  x.report('executor: simple scalar') do
    N.times { EXECUTOR.execute(QUERIES[:simple_scalar]) }
  end

  x.report('executor: list with scalars') do
    N.times { EXECUTOR.execute(QUERIES[:list_with_scalars]) }
  end

  x.report('executor: nested one level') do
    N.times { EXECUTOR.execute(QUERIES[:nested_one_level]) }
  end

  x.report('executor: nested two levels') do
    N.times { EXECUTOR.execute(QUERIES[:nested_two_levels]) }
  end

  x.report('executor: deeply nested') do
    N.times { EXECUTOR.execute(QUERIES[:deeply_nested]) }
  end

  x.report('executor: single orchard') do
    N.times { EXECUTOR.execute(QUERIES[:single_orchard]) }
  end

  x.report('executor: single orchard nested') do
    N.times { EXECUTOR.execute(QUERIES[:single_orchard_nested]) }
  end

  x.report('executor: all varieties') do
    N.times { EXECUTOR.execute(QUERIES[:all_varieties]) }
  end

  x.report('executor: all harvests') do
    N.times { EXECUTOR.execute(QUERIES[:all_harvests]) }
  end

  x.report('executor: harvests with variety') do
    N.times { EXECUTOR.execute(QUERIES[:harvests_with_variety]) }
  end

  x.report('executor: mutation addHarvest') do
    N.times do
      EXECUTOR.execute(QUERIES[:mutation])
      Saratoga::Store.reset! # keep store from growing across iterations
    end
  end
end
