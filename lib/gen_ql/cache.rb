# frozen_string_literal: true

module GenQL
  # Thread-safe in-memory query-result cache with optional per-entry TTL.
  #
  # Each entry may carry an optional TTL (time-to-live in seconds). Entries
  # without a TTL never expire. Expired entries are evicted lazily on access.
  #
  # Usage:
  #   cache    = GenQL::Cache.new
  #   executor = GenQL::Executor.new(schema, cache: cache)
  #
  #   # Direct cache access
  #   value = cache.fetch("{ orchards { name } }", ttl: 60) { executor.run(...) }
  #   cache.delete("{ orchards { name } }")
  #   cache.clear
  class Cache
    # Internal struct that pairs a cached value with an optional expiry time.
    # Uses Process::CLOCK_MONOTONIC so TTLs are unaffected by wall-clock adjustments.
    Entry = Struct.new(:value, :expires_at) do
      def expired?
        expires_at && Process.clock_gettime(Process::CLOCK_MONOTONIC) > expires_at
      end
    end
    private_constant :Entry

    def initialize
      @store = {}
      @mutex = Mutex.new
    end

    # Return the cached value for +key+, or +nil+ if missing or expired.
    #
    # @param key [String]
    # @return [Object, nil]
    def read(key)
      @mutex.synchronize do
        entry = @store[key]
        return nil if entry.nil? || entry.expired?

        entry.value
      end
    end

    # Store +value+ under +key+ with an optional +ttl+ in seconds.
    #
    # @param key   [String]
    # @param value [Object]
    # @param ttl   [Numeric, nil]  seconds until expiry; +nil+ means never
    # @return      [Object]  the stored value
    def write(key, value, ttl: nil)
      expires_at = ttl ? Process.clock_gettime(Process::CLOCK_MONOTONIC) + ttl : nil
      @mutex.synchronize { @store[key] = Entry.new(value, expires_at) }
      value
    end

    # Return the cached value for +key+ if present and unexpired; otherwise
    # call the block, store its return value, and return it.
    #
    # @param key [String]
    # @param ttl [Numeric, nil]
    # @yieldreturn [Object]
    # @return     [Object]
    def fetch(key, ttl: nil)
      cached = read(key)
      return cached unless cached.nil?

      result = yield
      write(key, result, ttl: ttl)
      result
    end

    # Remove the entry for +key+.
    #
    # @param key [String]
    def delete(key)
      @mutex.synchronize { @store.delete(key) }
    end

    # Remove all entries.
    def clear
      @mutex.synchronize { @store.clear }
    end

    # Number of stored entries (may include expired entries not yet evicted).
    #
    # @return [Integer]
    def size
      @mutex.synchronize { @store.size }
    end

    # Evict all expired entries and return the number removed.
    #
    # @return [Integer]
    def evict_expired
      removed = 0
      @mutex.synchronize do
        @store.delete_if do |_key, entry|
          if entry.expired?
            removed += 1
            true
          else
            false
          end
        end
      end
      removed
    end
  end
end
