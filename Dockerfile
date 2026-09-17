FROM ruby:3.4.10-slim-bookworm

ENV BUNDLE_DEPLOYMENT=true \
    BUNDLE_WITHOUT=development:test \
    RACK_ENV=production \
    SARATOGA_ENV=production \
    SARATOGA_DATABASE_PATH=/app/data/saratoga.db

WORKDIR /app

RUN apt-get update \
    && apt-get install --no-install-recommends -y build-essential libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./
RUN gem install bundler --version 4.0.9 \
    && bundle install \
    && apt-get purge -y --auto-remove build-essential

COPY . .
RUN useradd --create-home --shell /usr/sbin/nologin app \
    && mkdir -p /app/data \
    && chown -R app:app /app

USER app
EXPOSE 9292

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD ["ruby", "-rnet/http", "-e", "exit(Net::HTTP.get_response(URI(\"http://127.0.0.1:#{ENV.fetch('PORT', 9292)}/health/ready\")).is_a?(Net::HTTPSuccess) ? 0 : 1)"]

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb", "config.ru"]
