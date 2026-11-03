# Fixed local-demo environment; availability and provider compatibility are environment-specific.
FROM ruby:4.0.9-trixie@sha256:42c18f0c9807ba1349c0253617d7f08ef98b815463b2f7785d97c4efdfd80f4d
WORKDIR /demo
COPY Gemfile Gemfile.lock ./
COPY test/installed_gem_check.rb test/installed_gem_check.rb
RUN gem fetch ap2_mandate_verifier --version 1.1.0 && \
    test "$(wc -c < ap2_mandate_verifier-1.1.0.gem)" -eq 115200 && \
    echo '4c64cf5b6c61ae4395577828093a6f4022c35cf18b6ad1bcfcb9f95fbb4f43c9  ap2_mandate_verifier-1.1.0.gem' | sha256sum -c - && \
    mkdir -p vendor/cache && \
    mv ap2_mandate_verifier-1.1.0.gem vendor/cache/ && \
    BUNDLE_FROZEN=true bundle install && \
    cp Gemfile.lock /tmp/resolved-Gemfile.lock && \
    bundle exec ruby test/installed_gem_check.rb
COPY . .
ENV RAILS_ENV=development
EXPOSE 3000
CMD ["bundle", "exec", "puma", "-b", "tcp://0.0.0.0:3000", "-t", "1:1", "config.ru"]
