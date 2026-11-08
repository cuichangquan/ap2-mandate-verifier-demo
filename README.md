[English](README.md) | [日本語](README.ja.md)

# AP2 Ruby SDK 1.6.0: local learning demo

Try signed purchase approvals, Checkout and Payment Mandates, and Receipts with the published **ap2_mandate_verifier 1.6.0** gem. The browser demos and Ruby examples show what an agent may purchase, how a merchant verifies that permission, and how the buyer checks the reported result.

**All data, keys and payment effects are synthetic. No real money moves. Successful verification is not a successful payment.** The SDK is framework-independent; only this repository's browser interfaces use Rails.

AP2 supplies the signed purchase and payment documents used here. A2A carries messages between agents in the separate purchase demo. You do not need prior experience with either protocol, an external LLM, a payment account or an issuer account.

## Choose a starting point

| Demo | What to try | What to observe |
| --- | --- | --- |
| Standard browser demo, port **3000** | Valid, tampered, expired and missing-currency inputs; merchant signatures; multiple products and quantities | Verification status, diagnostic codes, Evidence and authentic Success/Error Receipts |
| A2A × AP2 purchase demo, port **3100** | Explicit approval, agent execution, eight scenarios, status refresh, recovery and history | Four separate stages: AP2 verification, application execution decision, simulated payment and buyer-side Receipt verification |
| Offline Ruby examples | Checkout → Payment, selective disclosure, execution policies, durable acceptance and long-lived Open Mandates | Public SDK APIs and the application responsibilities around them |

Both browser demos start in **English**. Use **English / 日本語** at the top of each screen. The language stays selected through navigation, form submissions, redirects and reloads. Unsupported language values fall back to English. Switching language does not rerun a purchase or change its ID, approval, quantity, amount or currency.

For a shorter guided tour, see [Quick Start](docs/QUICK_START.md). The commands below are run from this repository's root.

## Prerequisites and Docker startup

Install Git and Docker with Compose support. The Dockerfiles support Linux ARM64 and AMD64 containers and select pinned artifacts for each architecture. Apple Silicon runs ARM64 natively; AMD64 there is emulated. The build needs network access to fetch official images and locked gems. You do **not** need Ruby, Rails, a database or Redis on your host.

```sh
git clone https://github.com/cuichangquan/ap2-mandate-verifier-demo.git
cd ap2-mandate-verifier-demo
# Use amd64 instead on an x86_64 host.
export DEMO_ARCH=arm64
docker build --platform "linux/$DEMO_ARCH" -t ap2-mandate-verifier-demo:local .
docker run --rm --name ap2-mandate-verifier-demo \
  --cpus 1 --memory 512m --pids-limit 128 -p 127.0.0.1:3000:3000 \
  ap2-mandate-verifier-demo:local \
  timeout 3600 bundle exec puma -b tcp://0.0.0.0:3000 -t 1:1 config.ru
```

Open **http://127.0.0.1:3000/**. The web process stops after one hour. To stop it sooner, run `docker stop ap2-mandate-verifier-demo` in another terminal. The container is removed automatically; the built image remains. Do not expose these demos to the internet or prune shared Docker caches.

The standard demo uses host port 3000 and the purchase demo uses 3100, so they can run together. [Docker platform details and reproduction record (English/Japanese)](docs/DOCKER_PORTABILITY_160.md) distinguish native runs from emulation and historical results from current-commit CI.

## Explore the standard browser demo

1. At `/`, choose a scenario and run verification. Compare the status, machine-readable code, diagnostics and whether Evidence exists.
2. Open `/merchant` from the navigation. Compare merchant signatures and the authentic Success and Error Receipts.
3. Open `/multi-item`. Compare Coffee × 2 plus Tea × 3 with the short order containing only Tea × 2.
4. Switch to Japanese and back. The selected scenario and its result should remain the same. Results are display snapshots held in process-local memory for 30 minutes. Language links never regenerate an expired or missing result. Direct merchant/multi-item visits after session loss and explicit rerun URLs can create fresh synthetic results; see the [snapshot behavior](docs/LOCALIZATION.md#standard-demo-result-snapshots). Amounts retain their explicit currency, including USD in the standard fixtures and JPY in the purchase demo.

| Case | Expected result |
| --- | --- |
| Valid | `verified_research` / `scoped_research_verified`; Evidence present |
| Tampered purchase | `rejected` / `host_binding_mismatch`; no Evidence |
| Expired | `rejected` / `invalid_purchase_time`; no Evidence |
| Missing currency | `rejected` / `invalid_host_context`; `order.currency` diagnostic; no Evidence |
| Merchant signature + Success Receipt | Authenticity `true`; reported purchase success `true` |
| Merchant signature + Error Receipt | Authenticity `true`; reported purchase success `false`; reported rejection `true` |
| Coffee × 2 + Tea × 3 | Multi-item profile verifies; Evidence present |
| Second item reduced to Tea × 2 | `constraint_mismatch`, despite a valid signature and matching amount; no Evidence |

**Evidence and Receipt authenticity are not permission to execute a purchase or payment.** A Receipt authenticates an application's reported outcome. An authentic Error is still a failure; a valid signature alone does not establish settlement. These standard screens do not execute payments, update real orders or consume production nonces.

## Run the A2A × AP2 purchase demo

This separate Compose stack uses published `ap2_mandate_verifier 1.6.0` and `a2a-rails 0.3.0` without modifying either gem. Authority, buyer and seller run in separate processes; agent communication uses real local HTTPS.

```sh
export COMPOSE_PROJECT_NAME=ap2-purchase-demo
docker compose -f compose.purchase.yml up --build
```

1. Open **http://127.0.0.1:3100/** and select the valid scenario.
2. Review Tea × 3, a total limit of **3,000 JPY**, Tea Shop and the simulated payment terms. Check the explicit-approval checkbox and save the approval. Approval alone does not execute a purchase.
3. Run the agent for that purchase ID. The normal offer is **3 × 800 JPY = 2,400 JPY**.
4. Read all four stages and the execution count. Success requires the buyer to verify the matching Success Receipt, not just AP2 verification.
5. Re-run the **same purchase ID** and confirm that the simulated processor count remains **1**. Try `timeout`, refresh status and recover using the saved result without creating another purchase.

The [complete purchase guide](docs/PURCHASE_DEMO.md) covers all eight scenarios, errors and unknown outcomes, restart/recovery, purchase history, trust boundaries and tests. The purchase UI retains history only for approvals owned by the current browser session. Keep using the same hostname and browser session.

```sh
# Run in a terminal with the same COMPOSE_PROJECT_NAME.
docker compose -f compose.purchase.yml restart buyer seller
docker compose -f compose.purchase.yml down
```

Ordinary `down` preserves the named volumes and purchase data. Do not delete volumes to recover a pending purchase. Full-reset consequences are explained in the purchase guide.

## Run the offline Ruby examples

Once the standard image is built, run Checkout followed by Payment:

```sh
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-mandate-verifier-demo:local timeout 120 bundle exec ruby examples/checkout.rb
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-mandate-verifier-demo:local timeout 120 bundle exec ruby examples/payment.rb
```

Checkout issues Open, lets an Agent close and present it, and verifies against independent Host inputs. Expect `verified=true; rows=3; requirements=2`. Payment demonstrates Direct and conditional Mandates bound to Checkout and prints `Direct and conditional Payment: verified`. Both demonstrate authentic Success/Error Receipts without printing private keys or complete signed documents.

Use the same command with any of these files:

| File | Coverage and limits |
| --- | --- |
| `examples/selective_payment.rb` | Five retained versus three transmitted disclosures; selected Payment and both Receipt outcomes. Unselected values, salts and full wire data are not printed. Candidate count, order and issuer-JWT linkability are not hidden. |
| `examples/selective_checkout.rb` | Selected merchant/product candidates followed by Payment; all requirements and quantities remain. Merchant and product choices are independent allowlists, not correlated conditions. |
| `examples/payment_policy.rb` | Direct, conditional and selective Payment with an explicit PISP/execution-date profile. Signed values are checked against independently trusted application plans and inclusive UTC boundaries. No QWAC authentication, scheduling or settlement is performed. |

### Durable acceptance and a twelve-month Open

An optional image adds pinned SQLite 2.10.2 without changing the standard Gemfile or lockfile. Use the same `DEMO_ARCH` selected for the standard image.

```sh
docker build --platform "linux/$DEMO_ARCH" -f Dockerfile.acceptance -t ap2-acceptance:local .
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-acceptance:local timeout 120 ruby examples/payment_acceptance.rb
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-acceptance:local timeout 120 ruby examples/long_payment_limits.rb
```

The acceptance example compares reservation, replay, atomic start, one simulated dispatch, an unknown result, reopening the same database and recovery of the original Receipt. Production requires a protected durable database shared by all workers, independently approved occurrences, processor idempotency and reconciliation. A timeout, a new UUID or recreating the database does not grant new permission.

The long-Open example advances a synthetic clock through twelve UTC months: **8,000 JPY/month, 96,000 JPY total**, within a **100,000 JPY** budget. It performs twelve simulated starts and original-Receipt recovery without a scheduler or a year-long wait. A separate approval reserves 40,000 JPY in January and February; March's valid signed input would total 120,000 JPY and is rejected. No Ticket is issued, reservations remain 80,000 JPY, and this rejection comparison starts no processor. Temporary databases are removed when the example ends. `examples/long_payment.rb` is also available in this image.

This bounded UTC-monthly JPY profile is **not full generic AP2 MONTHLY conformance**. Content lasts at most 400 days while presentation proofs stay short-lived. Long selective/PISP/date composition, daily splitting, catch-up and automatic allowance refunds are unsupported. See the [SDK long-Payment contract](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/LONG_PAYMENT.md).

## Tests and translation maintenance

```sh
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-mandate-verifier-demo:local timeout 900 sh test/docker_validation.sh normal
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-acceptance:local timeout 600 sh test/docker_validation.sh acceptance
# With the purchase stack running; creates synthetic purchases and restarts agents.
sh test/purchase_docker_validation.sh
```

For locale behavior, translation updates, legacy stored Japanese values and the verification checklist, see [Localization](docs/LOCALIZATION.md). The [purchase validation record (English, historical)](docs/PURCHASE_VALIDATION.md), [published 1.6.0 record (Japanese, historical)](docs/PUBLISHED_160.md) and [Docker record (English/Japanese)](docs/DOCKER_PORTABILITY_160.md) identify their tested environments and revisions. They are not a claim that a later commit passed. Check the relevant pull request for current-commit CI and review results.

## Supported scope and responsibility boundaries

- The standard multi-item profile is `ap2.checkout.single_merchant_multi_item` v1: up to eight lines, eight requirements and eight candidates per requirement. It fully allocates quantities by product ID, preserves repeated-product lines, supports overlapping candidate sets and rejects excess, shortage and double allocation. Requirement IDs and line IDs are distinct. The original `ap2.checkout.single_merchant_sku` v1 remains unchanged for the four basic cases.
- Multi-item tax, shipping, discounts, multiple merchants and real payments are out of scope. See the [multi-item contract](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/MULTI_ITEM_CHECKOUT.md) and [Python SDK interoperability differences](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/MULTI_ITEM_INTEROP.md).
- Direct APIs include `CheckoutJWT.verify` and `Buyer.issue_closed/present_closed/verify`, with a Direct Receipt profile for one merchant and one to eight lines. See the [complete Direct example](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/examples/direct_checkout.rb) and [API contract](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/BUYER_DIRECT_CHECKOUT.md). The standard screens are synthetic Open → Agent Closed scenarios, not a Direct authentication/approval interface.
- Applications own authentication, consent, protected approvals, Provider keys, independently current trust, revocation, orders/challenges/time, durable one-use state, final execution permission and processor reconciliation. The purchase stack illustrates some of these duties locally; it does not make them automatic SDK guarantees.
- Signed Mandates and Receipts, protocol keys and values, IDs and machine-readable codes are never translated. Human-readable UI explanations are localized. Research-profile verification is not general AP2 conformance, production issuer trust or proof of a real payment.

## Pinned environment and provenance

The demo pins MRI **4.0.9**, Bundler **4.0.20**, railties/actionpack **8.0.4**, Puma **6.6.1** and Minitest **5.27.0**. The verifier is **1.6.0**, with JSON **2.19.9**, JWT **3.3.0**, base64 **0.3.0**, OpenSSL gem **4.0.2** and Digest **3.2.1**. Architecture-specific official Ruby digests and frozen lockfiles are retained. Standalone SDK support for MRI 3.4.12/4.0.9 is separate from this Rails demo's fixed MRI 4.0.9 environment; other native OS/Ruby combinations are not claimed here.

The standard Dockerfile checks the published gem's **186,368 bytes** and SHA256 `62de85123e1379c538c9c4302b71a9c55c590162591169a4e335aaa03a8991f8` before installation, then supplies those same bytes to Bundler. It checks all **68** installed/archive payloads, dependencies, Ruby requirements and loading outside the source tree. The gem is not rebuilt. Release source [`964e572`](https://github.com/cuichangquan/ap2-mandate-verifier/tree/964e572dc16d886561293cf90ddb9e2c927346bf) has the same tree `c9a9faaec045a9854fded3c1b4db375332a5fa57` as reviewed candidate `98f7325a9dd0ee06739fe95e1306abe9b1c6ee5d`. Download, provider or dependency failures stop the build rather than relaxing checksums or locks.

`ScenarioVerifier` prepares, stores, restores and verifies signed inputs against independent current business state. It does not repair a stored binding/digest to match current values or infer trusted keys/orders from submitted data. Standard fixture clocks are fixed at `1800000000`, or `1800000101` for expiry.

See the [support contract](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/SUPPORT_CONTRACT.md), [merchant API and specification differences](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/MERCHANT_SIGNING.md), [MIT license](LICENSE), [third-party notices](THIRD_PARTY_NOTICES.md) and [fixture notice (English)](fixtures/input_builder/NOTICE.md). Logs, dependency archives and temporary session keys must not be committed.

### Historical candidate builds

Normal usage needs only the published-gem Dockerfiles above. `Dockerfile.candidate`, `Gemfile.candidate` and their separate lockfile remain a historical **0.6.0** source-comparison path, not a current 1.6.0 build recipe or evidence of published gem bytes. Do not mix that lockfile into normal startup. Earlier records remain available in [History (English/Japanese)](docs/HISTORY.md), [0.6.0 multi-item candidate (Japanese)](docs/MULTI_ITEM_CANDIDATE.md) and [older candidates (English, with Japanese scenario labels)](CANDIDATE.md).
