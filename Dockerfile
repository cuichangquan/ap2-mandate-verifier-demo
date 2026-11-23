# Fixed local-demo environment; availability and provider compatibility are environment-specific.
ARG TARGETARCH
FROM ruby:4.0.10-trixie@sha256:a78157a2cb8de55f7605b64538c8ffdc1ee15e2664065793d839250755e7cacc AS base-arm64
FROM ruby:4.0.10-trixie@sha256:d07e1fa51948cd92c126b019e7b7473af301440a807437fb2f617b6b005af8b1 AS base-amd64
FROM base-${TARGETARCH}
WORKDIR /demo
COPY Gemfile Gemfile.lock ./
COPY test/installed_gem_check.rb test/installed_gem_check.rb
RUN gem fetch ap2_mandate_verifier --version 1.7.0 && \
    test "$(wc -c < ap2_mandate_verifier-1.7.0.gem)" -eq 208384 && \
    echo '2a3da0706313fd6ef6bf05dd0aed2f05899a5690b42568b3ebd814b41ad17140  ap2_mandate_verifier-1.7.0.gem' | sha256sum -c - && \
    mkdir -p vendor/cache && \
    mv ap2_mandate_verifier-1.7.0.gem vendor/cache/ && \
    BUNDLE_FROZEN=true bundle install && \
    cp Gemfile.lock /tmp/resolved-Gemfile.lock && \
    bundle exec ruby test/installed_gem_check.rb
COPY . .
ENV RAILS_ENV=development
EXPOSE 3000
CMD ["bundle", "exec", "puma", "-b", "tcp://0.0.0.0:3000", "-t", "1:1", "config.ru"]
