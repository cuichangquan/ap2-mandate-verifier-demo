# Acquisition/build pending approval. Availability and provider compatibility unverified.
FROM ruby:4.0.9-trixie@sha256:42c18f0c9807ba1349c0253617d7f08ef98b815463b2f7785d97c4efdfd80f4d
WORKDIR /demo
COPY Gemfile Gemfile.lock ./
RUN gem fetch ap2_mandate_verifier --version 0.1.0 && \
    test "$(wc -c < ap2_mandate_verifier-0.1.0.gem)" -eq 34304 && \
    echo '37b2a235b6fab2d9d9765ae985dd9db27afd3b2c5407fe263a6b65314550db32  ap2_mandate_verifier-0.1.0.gem' | sha256sum -c - && \
    mkdir -p vendor/cache && \
    mv ap2_mandate_verifier-0.1.0.gem vendor/cache/ && \
    BUNDLE_FROZEN=true bundle install && \
    cp Gemfile.lock /tmp/resolved-Gemfile.lock
COPY . .
ENV RAILS_ENV=development
EXPOSE 3000
CMD ["bundle", "exec", "puma", "-b", "tcp://0.0.0.0:3000", "-t", "1:1", "config.ru"]
