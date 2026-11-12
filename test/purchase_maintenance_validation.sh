#!/bin/sh
set -eu
# Destructive TLS fault fixtures are permitted ONLY in an explicitly isolated QA project.
[ "${PURCHASE_MAINTENANCE_QA:-}" = 1 ] || { echo 'Set PURCHASE_MAINTENANCE_QA=1 for an isolated synthetic project.' >&2; exit 2; }
compose() { docker compose -f compose.purchase.yml "$@"; }
fixture() { compose run --rm --no-deps -e PURCHASE_TLS_FIXTURE=1 init bundle exec ruby test/purchase_tls_fixture.rb "$1"; }
probe() { compose run --rm --no-deps init bundle exec ruby test/purchase_maintenance_probe.rb "$1"; }
sh bin/purchase-demo status
compose exec -T authority bundle exec ruby test/purchase_maintenance_probe.rb seed
compose stop -t 30 authority buyer seller
probe snapshot
fixture expired
if sh bin/purchase-demo diagnose; then echo 'Expired certificate incorrectly healthy'; exit 1; fi
sh bin/purchase-demo rotate
compose stop -t 30 authority buyer seller
probe compare
# Partial installation must block startup readiness, and recovery must resume safely.
fixture interrupt
if sh bin/purchase-demo diagnose; then echo 'Interrupted rotation incorrectly healthy'; exit 1; fi
sh bin/purchase-demo recover
compose stop -t 30 authority buyer seller
probe compare
compose up -d --no-build
attempt=0
until sh bin/purchase-demo status; do attempt=$((attempt+1)); test "$attempt" -lt 12; sleep 2; done
compose exec -T authority bundle exec ruby test/purchase_maintenance_probe.rb recover
# A stopped Seller disables operations; restoring it never submits a purchase.
compose stop seller
if sh bin/purchase-demo status; then echo 'Stopped Seller incorrectly ready'; exit 1; fi
compose start seller
attempt=0
until sh bin/purchase-demo status; do attempt=$((attempt+1)); test "$attempt" -lt 12; sleep 2; done
compose exec -T authority bundle exec ruby test/purchase_maintenance_probe.rb recover
printf '%s\n' 'Maintenance integration passed; no volumes deleted.'
