#!/bin/sh
set -eu
# Run from the repository root. Caller owns Compose lifecycle and fresh volume
# selection. This helper never removes volumes or shared images/cache.
COMPOSE="docker compose -f compose.purchase.yml"
$COMPOSE exec -T authority timeout 180 sh -c '
  bundle exec ruby test/purchase_protocol_test.rb &&
  bundle exec ruby test/purchase_transport_test.rb &&
  bundle exec ruby test/purchase_setup_test.rb &&
  bundle exec ruby test/purchase_runtime_test.rb &&
  bundle exec ruby test/purchase_ui_test.rb
'
$COMPOSE exec -T buyer timeout 30 bundle exec ruby test/purchase_tls_boundaries.rb
$COMPOSE exec -T authority timeout 180 bundle exec ruby test/purchase_integration.rb
concurrency_id=$($COMPOSE exec -T authority timeout 30 bundle exec ruby -r ./purchase_demo/runtime -e 'puts PurchaseDemo::Runtime.authority.approve(id: SecureRandom.uuid, scenario: "valid")')
$COMPOSE exec -T buyer timeout 30 bundle exec ruby test/purchase_http_concurrency.rb "$concurrency_id"
timeout_id=$($COMPOSE exec -T authority timeout 30 bundle exec ruby -r ./purchase_demo/runtime -e 'puts PurchaseDemo::Runtime.authority.approve(id: SecureRandom.uuid, scenario: "timeout")')
$COMPOSE exec -T buyer timeout 30 bundle exec ruby test/purchase_http_timeout.rb "$timeout_id"
$COMPOSE exec -T authority timeout 30 bundle exec ruby test/purchase_restart.rb before
$COMPOSE restart buyer seller
# Read-only health checks; no broad server logs or secret-bearing task dump.
i=0
until $COMPOSE exec -T authority bundle exec ruby -rnet/http -ropenssl -e '
  %w[buyer seller].each do |host|
    http = Net::HTTP.new(host, 3443, nil)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.ca_file = "/trust/ca.crt"
    http.open_timeout = http.read_timeout = 2
    abort unless http.get("/health").code == "200"
  end
' >/dev/null 2>&1; do
  i=$((i+1)); test "$i" -lt 30; sleep 1
done
$COMPOSE exec -T authority timeout 30 bundle exec ruby test/purchase_restart.rb after
