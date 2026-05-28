ARG RUBY_VERSION=latest
FROM ruby:${RUBY_VERSION}

WORKDIR /code

ENV BUNDLE_GEMFILE=/code/gems.rb \
    BUNDLE_WITHOUT=maintenance

RUN apt-get update && apt-get install -y \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY gems.rb gems.locked *.gemspec ./
COPY lib/async/service/supervisor/envoy/version.rb lib/async/service/supervisor/envoy/version.rb
RUN bundle install

COPY . .
