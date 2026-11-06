# Try published AP2 Ruby SDK 1.6.0 locally

[日本語 / complete Docker instructions](../README.md)

This optional Rails demo uses the framework-independent Ruby SDK. All keys,
orders, approvals, clocks and effects are synthetic. No production payment occurs.
Verification, reservation, authorization and settlement are separate.

## Build once

Requirements: Git and Docker, with Linux ARM64 or AMD64 containers.
The Dockerfiles select pinned Ruby and SQLite artifacts for each architecture.
Apple Silicon runs ARM64 natively and AMD64 through emulation. See the
[support and no-cache reproduction record](DOCKER_PORTABILITY_160.md) for exact
observations, native CI status boundaries and both-architecture commands.
This Rails demo pins MRI 4.0.9; the standalone SDK also supports MRI 3.4.12.
No host Ruby, Rails, DB or Redis installation is needed. First downloads can take
longer than the roughly ten-minute walkthrough.

```sh
git clone https://github.com/cuichangquan/ap2-mandate-verifier-demo.git
cd ap2-mandate-verifier-demo
docker build --platform linux/arm64 -t ap2-mandate-verifier-demo:local .
```

## Checkout, then Payment and Receipts

```sh
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-mandate-verifier-demo:local timeout 120 bundle exec ruby examples/checkout.rb
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-mandate-verifier-demo:local timeout 120 bundle exec ruby examples/payment.rb
```

Checkout issues Open, lets a registered Agent close/present it, and verifies
against independent Host inputs. Expected: `verified=true; rows=3; requirements=2`.
Payment adds Direct and conditional Payment Mandates bound to Checkout.
Both show alternative authentic Success/Error Receipts: authenticity true does
not imply reported success true, and does not establish settlement.
Try `examples/selective_checkout.rb` with the same command for selected candidates.

## Twelve months and budget rejection

```sh
docker build --platform linux/arm64 -f Dockerfile.acceptance -t ap2-acceptance:local .
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-acceptance:local timeout 120 ruby examples/long_payment_limits.rb
```

Only this optional image adds pinned SQLite 2.10.2; the normal lockfile is unchanged.
One Open pair covers twelve explicit synthetic 2028 UTC months: 8,000 JPY/month,
96,000 reserved against 100,000 JPY, twelve mock starts, original-Receipt recovery.
No year-long wait or scheduler. Temporary databases disappear after the example.

A separate approval reserves 40,000 in January and February. March's wire verifies,
and a third count slot remains, but 120,000 exceeds 100,000: `acceptance=rejected`,
`ticket=false`, reservations stay 80,000 / two occurrences. This comparison starts
no processor. Stateless verification alone does not enforce historical quotas.

Long content is bounded to 400 days while proofs stay short-lived. This local
UTC-monthly JPY profile is **not full generic AP2 MONTHLY conformance**. Long
selective/PISP/date composition, catch-up and automatic refunds are unsupported.
[Detailed contract](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/LONG_PAYMENT.md).

## Optional local screens

```sh
docker run --rm --name ap2-mandate-verifier-demo \
  --cpus 1 --memory 512m --pids-limit 128 -p 127.0.0.1:3100:3000 \
  ap2-mandate-verifier-demo:local \
  timeout 3600 bundle exec puma -b tcp://0.0.0.0:3000 -t 1:1 config.ru
```

Visit http://127.0.0.1:3100/ for valid/tampered/expired/missing-currency comparisons,
`/merchant` for authentic Success/Error Checkout Receipts, and `/multi-item` for
quantity-shortage rejection. Screens are Japanese; Payment/long Open use the Ruby
commands above. Stop with `docker stop ap2-mandate-verifier-demo`.

Apps own authentication, consent, protected approvals, independently current trust,
revocation, orders/challenges/time, shared durable one-use state, final permission,
processor idempotency and reconciliation. Unknown effects stay pending; timeout
or Error does not automatically reopen execution or refund allowance. Never reuse
these synthetic fixtures as production trust. [Test and publication evidence](PUBLISHED_160.md).
