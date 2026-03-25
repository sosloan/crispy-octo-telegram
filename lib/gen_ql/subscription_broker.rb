# frozen_string_literal: true

require 'securerandom'

module GenQL
  # Thread-safe, in-process pub/sub broker for GenQL subscriptions.
  #
  # Publishers call +SubscriptionBroker.publish(event_name, data)+ when an
  # event occurs (e.g. after a mutation).  Subscribers register a callback via
  # +SubscriptionBroker.subscribe(event_name) { |data| ... }+ and receive an
  # opaque subscription_id they can later pass to +unsubscribe+.
  module SubscriptionBroker
    MUTEX = Mutex.new
    private_constant :MUTEX

    class << self
      def subscribe(event_name, &callback)
        id = SecureRandom.uuid
        MUTEX.synchronize { ensure_subscribers[event_name.to_s] << { id: id, callback: callback } }
        id
      end

      def unsubscribe(subscription_id)
        MUTEX.synchronize do
          ensure_subscribers.each_value { |subs| subs.reject! { |s| s[:id] == subscription_id } }
        end
      end

      def publish(event_name, data)
        subs = MUTEX.synchronize { ensure_subscribers[event_name.to_s].dup }
        subs.each { |s| s[:callback].call(data) }
      end

      def reset!
        MUTEX.synchronize { @subscribers = nil }
      end

      private

      # Must be called within MUTEX.synchronize.
      def ensure_subscribers
        @subscribers ||= Hash.new { |h, k| h[k] = [] }
      end
    end
  end
end
