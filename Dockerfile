# Fixed local-demo environment; availability and provider compatibility are environment-specific.
FROM ruby:4.0.9-trixie@sha256:42c18f0c9807ba1349c0253617d7f08ef98b815463b2f7785d97c4efdfd80f4d
WORKDIR /demo
COPY Gemfile Gemfile.lock ./
RUN gem fetch ap2_mandate_verifier --version 0.3.0 && \
    test "$(wc -c < ap2_mandate_verifier-0.3.0.gem)" -eq 37376 && \
    echo 'b3a31d5a8b0718f1085745dd4d97d85f210ff9a1628798110da9ff382ae546bd  ap2_mandate_verifier-0.3.0.gem' | sha256sum -c - && \
    mkdir -p vendor/cache && \
    mv ap2_mandate_verifier-0.3.0.gem vendor/cache/ && \
    BUNDLE_FROZEN=true bundle install && \
    cp Gemfile.lock /tmp/resolved-Gemfile.lock
COPY . .
ENV RAILS_ENV=development
EXPOSE 3000
CMD ["bundle", "exec", "puma", "-b", "tcp://0.0.0.0:3000", "-t", "1:1", "config.ru"]
