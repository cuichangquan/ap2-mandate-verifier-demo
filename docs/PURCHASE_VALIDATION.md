# A2A + AP2 purchase demo validation ledger

Status (2026-11-07): **LOCAL ARM64 VALIDATION PASS / FINAL CI, INDEPENDENT REVIEW AND MERGE PENDING**.

These results were observed on the working tree based on
`1f90efa6342fa22f051a7da29c05382a4a2286b9`, including the final local UI/origin and
TLS fixes. They are not CI evidence for a committed final HEAD. Record that HEAD
and its CI/review results before declaring readiness to merge. No final image ID
was captured; an earlier, superseded image is deliberately not cited.

## Environment and reproducibility

- Host: MacBook Air, Apple Silicon; Docker Desktop 29.9.2.
- New demo: native Linux ARM64 containers, Ruby 4.0.9, Rails 8.0.4,
  SQLite driver 2.10.2. No Ruby/Gem installation on the host Mac.
- Validation project: `COMPOSE_PROJECT_NAME=ap2-purchase-validation`.
- Public Gem archives verified during build:
  - `ap2_mandate_verifier 1.6.0`: `62de85123e1379c538c9c4302b71a9c55c590162591169a4e335aaa03a8991f8`.
  - `a2a-rails 0.3.0`: `90a7d8d32bdd19ebc97046a3307c483cc0798b06afcd79df4931cfc5a4ead40f`.
- `Gemfile.purchase.lock` was resolved using the existing official Ruby Docker
  environment, not hand-written. SHA256:
  `e912bd44cf8f169a05782a45e6913f1ea5f4560d0cd8b34dfa699f425fef746e`.
- `Dockerfile.purchase` pins Ruby 4.0.9 Trixie base digests:
  - ARM64: `42c18f0c9807ba1349c0253617d7f08ef98b815463b2f7785d97c4efdfd80f4d`.
  - AMD64: `d1b33477de075536be34e1f50a15501c35151c380baba5e55a8c2b0b84ec9c7c`.
- The new purchase demo has **not** been locally validated on AMD64. Both
  architecture jobs remain final CI obligations; an AMD64 Dockerfile target is
  not itself a passing test.
- No SDK source change, candidate Gem, new Gem release, public deployment,
  external payment account or real-money execution was required.

Protocol scope: A2A 1.0 over JSON-RPC 2.0; application-defined AP2 payload in
message metadata and returned data Artifacts, not formal AP2 extension negotiation.
AP2 v0.2.0 reference remains pinned at
`b4587ac1d055888a73b4b21750973cffba961793`. Observed SDK profile identifiers are
`ap2.checkout.single_merchant_multi_item` and `ap2.payment.single.complete.1`.
Synthetic evidence is not generic AP2 certification or real-Issuer provenance.

## Commands and project isolation

The successful validation used the following project consistently:

```sh
export COMPOSE_PROJECT_NAME=ap2-purchase-validation
docker compose -f compose.purchase.yml up --build -d
sh test/purchase_docker_validation.sh
```

The helper executes the tests below, real TLS probes, concurrent A2A requests,
actual timeout/recovery and buyer/seller restart. It creates synthetic purchases
and never deletes volumes. `COMPOSE_PROJECT_NAME` must remain exported for the
helper and all subsequent Compose commands. The quick-start documentation uses
`ap2-purchase-demo` for normal use; these are intentionally different volume sets.

```sh
# Stop this validation project while preserving keys and ledgers.
COMPOSE_PROJECT_NAME=ap2-purchase-validation docker compose -f compose.purchase.yml down
```

Do not run `down -v` to make a test pass or to recover a missing ledger. It is a
separate, destructive full-reset choice that discards prior purchases.

## Observed automated results

Latest complete new-demo test-shell run: **46 tests / 399 assertions**, zero
failures, errors or skips.

| Test | Tests | Assertions | Result |
| --- | ---: | ---: | --- |
| `purchase_protocol_test.rb` | 6 | 41 | PASS |
| `purchase_transport_test.rb` | 5 | 17 | PASS |
| `purchase_setup_test.rb` | 5 | 48 | PASS |
| `purchase_runtime_test.rb` | 14 | 115 | PASS |
| `purchase_ui_test.rb` | 11 | 123 | PASS |
| `purchase_integration.rb` | 5 | 55 | PASS, actual separate-process TLS/A2A |

Additional live script checks passed and are not added to that Minitest count:

- `purchase_tls_boundaries.rb`: correct CA/hostname succeeds; untrusted CA and
  wrong hostname fail; buyer A2A bearer cannot authorize seller control; buyer
  does not possess issuer key or authority control access; unchanged production
  A2A outbound policy rejects loopback/private Docker destinations.
- `purchase_http_concurrency.rb`: four concurrent real A2A requests result in
  **one** durable mock processor effect and the original Receipt.
- `purchase_http_timeout.rb`: an actual `Transport` timeout was observed after
  the durable mock effect. Recovery returns the original Receipt, count **1**;
  no fresh approval, wire presentation or processor key is issued.
- `purchase_restart.rb`: actual buyer and seller restart preserves the purchase
  and original Receipt; recovery verifies it with execution count **1**.

The runtime unit tests replace Transport in-process. They establish application
logic/durability properties, not TLS. Those claims rely on the distinct live
scripts and integration tests above. The fixed-local transport does not weaken
or monkeypatch the published A2A client's production TLS/SSRF policy.

## Existing published-demo regression

The existing normal and acceptance images were rebuilt from the latest checkout.
The regression suites passed: **11 tests / 221 assertions**, all eight example
wrappers, no skips. The installed AP2 archive comparison matched **68 files**.
These results protect the old examples but are separate from the 46/399 new-demo
suite; they are not substituted for new-demo interoperability evidence.

## Observed browser QA

Actual Chrome, desktop and **390×844** layout: all eight scenarios passed.

| Scenario | Browser result | Durable mock count |
| --- | --- | ---: |
| valid | Genuine Success verified by buyer | 1 |
| budget | Refused before execution | 0 |
| quantity | Refused before execution | 0 |
| tampered | Refused before execution | 0 |
| error | Genuine Error; not purchase success | 1 |
| wrong_receipt | Receipt refused; no new payment | 1 |
| invalid_receipt | Receipt refused; no new payment | 1 |
| timeout | Unknown, replay still unknown, recovery verifies Success | 1 throughout |

Normal explicit approval, repeated execution, refresh and Back retained the same
purchase ID and count 1. Required approval checkbox was checked. A different
localhost versus 127.0.0.1 browser session could not read the original purchase
(404 and empty history). Desktop/mobile layout was clean. No screenshots were
delivered as part of this record.

One real-browser issue was found: `Referrer-Policy: no-referrer` yielded
`Origin: null` on a legitimate form submission. Changing the policy to
`same-origin` restored the intended form flow; CSRF and origin validation were
retained and verified. This was not fixed by disabling CSRF.

## Network and review findings

- `buyer` and `seller` join only the internal `purchase` network; no backend
  ports are published.
- `authority` joins `purchase` plus the `ui` bridge required for Docker Desktop
  loopback publication. Only `127.0.0.1:3100` is published. Authority is therefore
  not claimed to be network-egress-isolated.
- The SVG was rendered with the existing Inkscape tool and visually inspected
  during source preparation. The latest wording distinguishes the two networks.
- Earlier independent source review found and prompted fixes for an endless
  method load bug, untrusted seller-success labels surviving missing/Error
  Receipts, and post-dispatch uncertainty appearing as not started. Additional
  review corrected SDK pending recovery and rejection-reason preservation.
- Setup rejects missing/empty/insecure role state rather than silently replacing
  keys or ledgers. Certificate expiry and approval/challenge expiry do not trigger
  automatic reauthorization.

These findings and local passes do **not** constitute an independent final-HEAD
no-findings sign-off. Final diff review, exact-commit CI and merge are pending.
Keep required CI on zero-cost standard runners, within the existing maximum of
three workflow runs per PR. CI is final validation, not a development retry loop.

## Remaining release gates

1. Commit the final reviewed working tree and record its SHA.
2. Complete independent review and final security self-audit on that diff.
3. Pass required exact-HEAD CI, including both ARM64 and AMD64 new-demo jobs and
   existing regression checks. Record run URLs and actual outcomes.
4. Only then perform the explicitly authorized merge. No new Gem publication is
   needed because this work is application/demo integration only.

PR: pending. Final CI: pending. Final independent review: pending. Merge: pending.
Do not include keys, Mandate/Receipt JWTs, challenge values, authorization tokens
or full A2A bodies in evidence, screenshots or logs.
