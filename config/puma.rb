# frozen_string_literal: true

min_threads = Integer(ENV.fetch('PUMA_MIN_THREADS', 1))
max_threads = Integer(ENV.fetch('PUMA_MAX_THREADS', 5))

threads min_threads, max_threads
bind "tcp://0.0.0.0:#{ENV.fetch('PORT', 9292)}"
environment ENV.fetch('RACK_ENV', 'production')

pidfile ENV['PIDFILE'] if ENV['PIDFILE']
