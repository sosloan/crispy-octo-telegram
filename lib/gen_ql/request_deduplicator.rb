# frozen_string_literal: true

module GenQL
  # Thread-safe request deduplicator.
  #
  # Identical concurrent read requests (same key) are coalesced so that only
  # one caller executes the block; all other callers with the same key wait
  # and share the result.  After execution the result is stored in a
  # short-lived cache (controlled by +ttl+) to satisfy subsequent identical
  # requests without re-executing.
  #
  # Usage:
  #   deduplicator = GenQL::RequestDeduplicator.new
  #   result = deduplicator.execute(cache_key) { expensive_operation }
  class RequestDeduplicator
    # Default time-to-live (seconds) for cached results.
    DEFAULT_TTL = 5

    # @!visibility private
    CacheEntry = Struct.new(:result, :expires_at)

    def initialize(ttl: DEFAULT_TTL)
      @ttl       = ttl
      @mutex     = Mutex.new
      @in_flight = {} # key -> slot hash
      @cache     = {} # key -> CacheEntry
    end

    # Execute +block+ unless an in-flight or recently cached result for +key+
    # already exists, in which case the existing result is returned directly.
    #
    # Thread-safe: multiple concurrent callers with the same +key+ block until
    # the first caller's block completes, then all receive the same result.
    # If the block raises, the exception is propagated to all waiting callers.
    #
    # @param key [Object] any value that uniquely identifies the request
    # @yieldreturn [Object] the result to cache and return
    # @return [Object] the (possibly cached or shared) result
    def execute(key, &)
      our_slot  = nil
      wait_slot = nil

      @mutex.synchronize do
        # The expiry check and return happen inside the global lock, so
        # another thread cannot evict or overwrite the entry between the
        # two operations.
        entry = @cache[key]
        return entry.result if entry && entry.expires_at > Time.now

        if (existing = @in_flight[key])
          wait_slot = existing
        else
          our_slot = build_slot
          @in_flight[key] = our_slot
        end
      end

      return wait_for(wait_slot) if wait_slot

      run_as_executor(key, our_slot, &)
    end

    # Discard all cached results.
    # Useful in test environments to prevent stale data from bleeding across
    # examples.  In-flight requests are not affected.
    def clear!
      @mutex.synchronize { @cache.clear }
    end

    private

    def build_slot
      { cv: ConditionVariable.new, mx: Mutex.new, result: nil, error: nil, done: false }
    end

    def wait_for(slot)
      slot[:mx].synchronize { slot[:cv].wait(slot[:mx]) until slot[:done] }
      raise slot[:error] if slot[:error]

      slot[:result]
    end

    def run_as_executor(key, slot)
      result = yield
      slot[:result] = result
      @mutex.synchronize do
        @cache[key] = CacheEntry.new(result, Time.now + @ttl)
        @in_flight.delete(key)
      end
      result
    rescue StandardError => e
      slot[:error] = e
      @mutex.synchronize { @in_flight.delete(key) }
      raise
    ensure
      slot[:mx].synchronize do
        slot[:done] = true
        slot[:cv].broadcast
      end
    end
  end
end
