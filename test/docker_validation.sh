#!/bin/sh
# Run inside the built image; only synthetic fixtures, never network or host mounts.
set -eu
mode=${1:-normal}
case "$mode" in normal|acceptance) ;; *) exit 2 ;; esac
cat /etc/os-release
uname -m
ruby -v
ruby -rrbconfig -e 'puts "ruby_host_cpu=#{RbConfig::CONFIG.fetch("host_cpu")} ruby_platform=#{RUBY_PLATFORM}"'
bundle exec ruby test/installed_gem_check.rb
cmp Gemfile.lock /tmp/resolved-Gemfile.lock
if [ "$mode" = normal ]; then
  for test in test/demo_test.rb test/merchant_scenario_test.rb test/multi_item_scenario_test.rb test/demo_locale_test.rb; do
    timeout 120 bundle exec ruby "$test"
  done
  for example in checkout payment selective_checkout selective_payment payment_policy; do
    timeout 120 bundle exec ruby "examples/$example.rb"
  done
else
  ruby -e 'gem "sqlite3", "= 2.10.2"; require "sqlite3"; puts "SQLite gem=#{SQLite3::VERSION} platform=#{Gem.loaded_specs.fetch("sqlite3").platform}"'
  for example in payment_acceptance long_payment long_payment_limits; do
    timeout 120 ruby "examples/$example.rb"
  done
fi
