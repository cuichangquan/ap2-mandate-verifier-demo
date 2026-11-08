[English](QUICK_START.md) | [日本語](QUICK_START.ja.md)

# Try the AP2 Ruby SDK locally

This walkthrough starts with the browser, then runs Checkout and Payment in Ruby and a purchase between separate agents. All keys, orders, approvals, clocks and effects are synthetic. **No real payment occurs.** See the [README](../README.md) for the complete feature map and support boundaries.

## 1. Build the standard demo

Requirements: Git and Docker with Compose support and Linux ARM64 or AMD64 containers. No host Ruby, Rails, database or Redis installation is needed. The build downloads official images and locked gems, so the first run can take longer than the walkthrough itself. This Rails demo pins MRI 4.0.9; standalone SDK support for MRI 3.4.12 is separate.

```sh
git clone https://github.com/cuichangquan/ap2-mandate-verifier-demo.git
cd ap2-mandate-verifier-demo
# Use amd64 instead on an x86_64 host.
export DEMO_ARCH=arm64
docker build --platform "linux/$DEMO_ARCH" -t ap2-mandate-verifier-demo:local .
```

ARM64 on Apple Silicon is native; AMD64 there is emulated. The Dockerfiles select pinned Ruby and SQLite artifacts for each architecture. See the [platform and no-cache reproduction record (English/Japanese)](DOCKER_PORTABILITY_160.md).

## 2. Compare verification and Receipts in the browser

```sh
docker run --rm --name ap2-mandate-verifier-demo \
  --cpus 1 --memory 512m --pids-limit 128 -p 127.0.0.1:3000:3000 \
  ap2-mandate-verifier-demo:local \
  timeout 3600 bundle exec puma -b tcp://0.0.0.0:3000 -t 1:1 config.ru
```

Open **http://127.0.0.1:3000/**. English is the default; use **English / 日本語** at the top to switch. Your choice persists through forms, navigation and reloads. An unsupported language value falls back to English.

1. Choose the valid scenario, then **Verify with the gem**. Expect `verified_research` / `scoped_research_verified` and Evidence.
2. Try tampered purchase data, expiry and missing currency. Expect rejection and no Evidence. The missing-currency case identifies `order.currency`; the machine-readable codes do not change with language.
3. Follow **Try merchant signatures and Success / Error Receipts** to `/merchant`. Both Receipts are authentic, but only Success reports purchase success. An authentic Error is a rejection.
4. Follow **Try multiple products and quantities** to `/multi-item`. Coffee × 2 and Tea × 3 verifies. Reducing Tea to 2 is rejected with `constraint_mismatch` despite a valid signature and matching amount.
5. Switch languages on a result and reload that display URL. Language links include `view=1` and never re-run verification, even when a snapshot is missing. Ordinary reloads reuse results while the same session and process-local cache remain valid. Snapshots last 30 minutes and disappear on server restart. Direct `/merchant` or `/multi-item` visits after session loss are treated as first visits and run the synthetic demo again; reloading an explicit `?run=1` URL also reruns it. Use the language/display links to inspect saved results. A cached result is not fresh execution permission.

The standard pages show Checkout verification and Receipt APIs, not real payment execution. Payment and long-Open examples are below. Stop the web container from another terminal with `docker stop ap2-mandate-verifier-demo`; it also stops automatically after one hour.

## 3. Checkout, then Payment and Receipts

```sh
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-mandate-verifier-demo:local timeout 120 bundle exec ruby examples/checkout.rb
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-mandate-verifier-demo:local timeout 120 bundle exec ruby examples/payment.rb
```

Checkout issues Open, lets a registered Agent close and present it, and verifies against independent Host inputs. Expect `verified=true; rows=3; requirements=2`. Payment adds Direct and conditional Mandates bound to Checkout. Expect `Direct and conditional Payment: verified`.

Both show authentic Success and Error Receipts. Authenticity `true` does not imply reported success `true` or prove settlement. Use the same command with `examples/selective_checkout.rb`, `examples/selective_payment.rb` or `examples/payment_policy.rb` for selective disclosure and execution policies. Full signed documents, private keys and undisclosed values are not printed.

## 4. Approve and run a purchase between agents

From the repository root in another terminal:

```sh
export COMPOSE_PROJECT_NAME=ap2-purchase-demo
docker compose -f compose.purchase.yml up --build
```

Open **http://127.0.0.1:3100/**. This separate stack can run alongside the standard demo on port 3000.

1. Select the valid scenario and review **Tea × 3, maximum 3,000 JPY** at Tea Shop. Check the explicit-approval box, then save the approval.
2. Run the agent for the displayed purchase ID. The normal offer is **2,400 JPY**. Approval and execution are separate actions.
3. Read **AP2 verification**, **application execution decision**, **mock payment result** and **Receipt verification** separately. The processor count should be **1**, and the buyer must verify the corresponding Success Receipt.
4. Re-run the same ID. The processor count must remain 1. A newly approved purchase has a new ID and is not a replay test.
5. Approve the `timeout` scenario. After running it, the result is unknown. Refresh and recover that **same ID** from its saved result; do not create a replacement purchase. Recovery must retain a count of 1 and verify the original Receipt.
6. Switch language on the result and open a purchase from browser-owned history. The ID, terms and execution count must not change.

The [purchase guide](PURCHASE_DEMO.md) explains all eight scenarios, invalid Receipts, error handling, session ownership, restarts, expiry and full reset. No external LLM, real card, payment account or issuer is needed.

```sh
# Keep the same COMPOSE_PROJECT_NAME for these commands.
docker compose -f compose.purchase.yml restart buyer seller
docker compose -f compose.purchase.yml down
```

`down` keeps named volumes. Do not remove them to resolve an unknown outcome. Only approvals owned by the current browser session appear in history; keep the hostname and browser session unchanged.

## 5. Optional: twelve months and budget rejection

Build the standard image first and retain the same `DEMO_ARCH`:

```sh
docker build --platform "linux/$DEMO_ARCH" -f Dockerfile.acceptance -t ap2-acceptance:local .
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-acceptance:local timeout 120 ruby examples/long_payment_limits.rb
```

Only this optional image adds pinned SQLite 2.10.2; the normal lockfile is unchanged. One Open pair covers twelve synthetic 2028 UTC months: **8,000 JPY/month**, **96,000 JPY** reserved against **100,000 JPY**, twelve simulated starts and original-Receipt recovery. No year-long wait or scheduler is needed. Temporary databases disappear after the example.

A separate approval reserves 40,000 JPY in January and again in February. March's wire verifies and a third count slot remains, but a total of 120,000 JPY exceeds the budget: `acceptance=rejected`, `ticket=false`, and reservations stay at 80,000 JPY / two occurrences. This comparison starts no processor. Stateless verification alone does not enforce historical quotas.

Long content is bounded to 400 days while proofs remain short-lived. This local UTC-monthly JPY profile is **not full generic AP2 MONTHLY conformance**. Long selective/PISP/date composition, daily splitting, catch-up and automatic allowance refunds are unsupported. See the [detailed SDK contract](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/LONG_PAYMENT.md).

## What remains the application's responsibility

Applications own authentication, consent, protected approvals, current independent trust, revocation, orders/challenges/time, durable shared one-use state, final execution permission, processor idempotency and reconciliation. Unknown effects remain pending. Timeout or Error does not automatically reopen execution or refund allowance. Never reuse these synthetic fixtures as production trust.

For test commands and published-gem provenance, return to the [README](../README.md). See [Localization](LOCALIZATION.md) for maintaining both languages. Historical [published 1.6.0 evidence (Japanese)](PUBLISHED_160.md) is kept separately from verification of the current change.
