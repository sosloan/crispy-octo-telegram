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

# ---------------------------------------------------------------------------
# Concurrent-user benchmark — 2,001 simultaneous users
#
# Spawns 2,001 threads that are held behind a barrier and released all at
# once.  Each thread executes one read-only GenQL query and records its own
# wall-clock latency.  After all threads finish, aggregate statistics are
# printed: throughput (req/s) and latency percentiles (p50 / p95 / p99).
#
# Read-only queries are used deliberately so that the shared in-memory store
# is never mutated during the run, removing the need for store-level locking.
# ---------------------------------------------------------------------------

CONCURRENT_USERS = 2_001

CONCURRENT_QUERIES = [
  QUERIES[:simple_scalar],
  QUERIES[:list_with_scalars],
  QUERIES[:nested_one_level],
  QUERIES[:single_orchard],
  QUERIES[:all_varieties],
  QUERIES[:all_harvests],
  QUERIES[:harvests_with_variety],
  QUERIES[:deeply_nested]
].freeze

# Spawn +users+ threads.  Each thread waits on the barrier stored in +barrier_context+,
# then executes one query and records its elapsed time.
def build_concurrent_threads(users, queries, barrier_context) # rubocop:disable Metrics/AbcSize
  barrier_mx = barrier_context[:barrier_mx]
  barrier_cv = barrier_context[:barrier_cv]
  ready      = barrier_context[:ready]
  go         = barrier_context[:go]
  latencies  = barrier_context[:latencies]
  errors     = barrier_context[:errors]
  err_mx     = barrier_context[:err_mx]
  users.times.map do |i|
    Thread.new do
      barrier_mx.synchronize do
        ready[0] += 1
        barrier_cv.wait(barrier_mx) until go[0]
      end
      t0           = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result       = EXECUTOR.execute(queries[i % queries.length])
      latencies[i] = Process.clock_gettime(Process::CLOCK_MONOTONIC) - t0
      err_mx.synchronize { errors[0] += 1 } if result[:errors]
    end
  end
end

# Run the concurrent benchmark and return a stats hash.
def run_concurrent_benchmark(users, queries)
  barrier_context = {
    barrier_mx: Mutex.new,
    barrier_cv: ConditionVariable.new,
    ready: [0],
    go: [false],
    latencies: Array.new(users),
    errors: [0],
    err_mx: Mutex.new
  }
  threads = build_concurrent_threads(users, queries, barrier_context)
  sleep 0.001 until barrier_context[:barrier_mx].synchronize { barrier_context[:ready][0] == users }
  wall_t = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  barrier_context[:barrier_mx].synchronize do
    barrier_context[:go][0] = true
    barrier_context[:barrier_cv].broadcast
  end
  threads.each(&:join)
  wall = Process.clock_gettime(Process::CLOCK_MONOTONIC) - wall_t
  { samples: barrier_context[:latencies].compact, wall: wall, errors: barrier_context[:errors][0] }
end

# Print a human-readable summary of concurrent benchmark results.
def print_concurrent_results(users, stats) # rubocop:disable Metrics/AbcSize
  sorted = stats[:samples].sort
  count  = sorted.length
  wall   = stats[:wall]
  mean   = stats[:samples].sum / count
  ms     = ->(s) { (s * 1_000).round(3) }
  pct    = ->(f) { sorted[(count * f).floor] }
  rows = {
    'Users:' => users.to_s,
    'Wall time:' => "#{wall.round(3)} s",
    'Throughput:' => "#{(users / wall).round(1)} req/s",
    'Min latency:' => "#{ms[sorted.first]} ms",
    'Mean latency:' => "#{ms[mean]} ms",
    'p50 latency:' => "#{ms[pct[0.50]]} ms",
    'p95 latency:' => "#{ms[pct[0.95]]} ms",
    'p99 latency:' => "#{ms[pct[0.99]]} ms",
    'Max latency:' => "#{ms[sorted.last]} ms",
    'Errors:' => stats[:errors].to_s
  }
  rows.each { |label, value| puts "#{label.ljust(20)} #{value}" }
end

puts "\n#{'=' * 60}"
puts "Concurrent-user benchmark  —  #{CONCURRENT_USERS} simultaneous users"
puts '=' * 60

concurrent_stats = run_concurrent_benchmark(CONCURRENT_USERS, CONCURRENT_QUERIES)
print_concurrent_results(CONCURRENT_USERS, concurrent_stats)

puts '=' * 60
