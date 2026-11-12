[English](PURCHASE_DEMO.md) | [日本語](PURCHASE_DEMO.ja.md)

# Buyer Agent × Seller Agent: local AP2 / A2A purchase demo

Approve **three bags of tea for no more than 3,000 JPY**, then follow a buyer and seller through **real HTTPS communication between separate processes**. Observe approval, verification, application acceptance, a simulated payment and buyer-side Receipt verification as separate steps.

**Only synthetic data is used. No real money moves. No external LLM, payment account, real card, external issuer or cloud service is needed.** This Compose stack is separate from the standard browser demo. The standard README uses host port **3000**; this purchase UI uses **3100**, so both can run together. Return to the [README](../README.md) or [Quick Start](QUICK_START.md) for the other demos.

## 1. Startup and your first purchase

Dependencies are pinned in `Gemfile.purchase.lock`. You need Git, Docker and Compose, not Ruby or gems installed on your host. From the repository root:

```sh
export COMPOSE_PROJECT_NAME=ap2-purchase-demo
docker compose -f compose.purchase.yml up --build
```

Use the same terminal, or set the same `COMPOSE_PROJECT_NAME` in subsequent terminals. A different project name creates separate volumes and purchase history. Docker selects the host's architecture; the purchase Dockerfile contains pinned Linux ARM64 and AMD64 base images.

The first `init` creates role-specific private keys, short-lived test certificates, random authentication tokens and SQLite data. The `authority`, `buyer` and `seller` services then run as separate processes.

1. Open **http://127.0.0.1:3100/**. English is the default. Select **日本語** at the top for Japanese.
2. Select the valid scenario and review Tea × 3, the 3,000 JPY limit, the merchant and simulated-payment terms.
3. Check the explicit-approval checkbox and choose **Approve these terms**. Saving approval does not execute the purchase.
4. Choose **Run Agent / retry the same purchase** for that ID. The normal offer is **3 × 800 JPY = 2,400 JPY**.
5. Read AP2 verification, application execution decision, mock payment result and Receipt verification separately, together with the execution count.

Wait for the readiness panel before using purchase actions. If readiness changes during a purchase, retain the same purchase ID.

### Language, ownership and navigation

**English / 日本語** appears on every purchase page, including results and history. Language persists through forms, redirects, navigation and reloads. Unsupported values fall back to English. A language switch uses the owned purchase's saved summary; it does not issue an approval, run the agent, poll the processor or perform recovery. **Refresh status** explicitly polls the current status. Language selection itself is request-scoped, so one request does not change another user's language.

Keep the same hostname (`127.0.0.1`) and browser session. The UI displays only purchases approved by that session. A different browser, private session or hostname does not acquire access merely by knowing a purchase ID. Use the purchase-history links to return to an existing purchase. Language does not change quantities, JPY amounts, approval terms, IDs or execution counts. Protocol values, signed Mandates/Receipts and machine-readable codes are not translated.

## Readiness and data-preserving TLS maintenance

From the repository root, use the **same Compose project name every time**:

```sh
export COMPOSE_PROJECT_NAME=ap2-purchase-demo
sh bin/purchase-demo start       # build/start; bounded readiness wait
sh bin/purchase-demo status      # live, read-only readiness and TLS checks
sh bin/purchase-demo diagnose    # disk certificate diagnosis, also while stopped
sh bin/purchase-demo stop        # retain all purchase volumes
sh bin/purchase-demo rotate      # stop, replace TLS set, restart and verify
```

The screen distinguishes **Preparing**, **Available**, **Cannot connect** and **Certificate renewal required**. It refreshes diagnostic state without approving, running, polling a payment result or recovering a purchase. Actions are checked again on the server, so an old page cannot bypass readiness. Cached history remains readable while another role is down. A status failure is not evidence that a payment failed: retain the original purchase ID and explicitly refresh/recover after readiness returns. Never create a second approval to work around a communication error.

`status` checks initialized files, storage and required communication paths with real CA and hostname verification. Its wait/retry limit is finite; nonzero exit means readiness was not established. `diagnose` reports the CA/Buyer/Seller certificate deadlines and remaining seconds, with a warning within 48 hours of expiry, and distinguishes observed expiry, key mismatch, CA inconsistency and unknown connection failures. Public on-disk certificate metadata is not proof of a successful live connection. No command weakens TLS or prints private keys, tokens or signed documents.

`rotate` temporarily stops **all three roles**, allowing up to 30 seconds for shutdown. An interrupted purchase remains associated with its original ID and saved state. Only TLS private keys, service certificates and CA/public certificate trust information change. Purchase IDs, approvals, original Mandates/Receipts, acceptance and processor records, AP2 signing keys, authentication tokens and the session secret remain. Use the same browser, hostname and cookies to retain history access. Approval, challenge and Receipt deadlines are **not extended**. Unknown payments are never automatically dispatched again.

Rotation stages one consistent CA/Buyer/Seller set and records pending maintenance before replacement. During an incomplete rotation purchase operations fail closed. Services resume only after the set is consistent; the wrapper then verifies live readiness. A verification failure stops services again and retains data. Successful output ends with `TLS rotation verified; purchase data retained.`

### Interrupted or failed update

```sh
# Inspect without starting or resetting the data:
sh bin/purchase-demo diagnose
# Resume the saved TLS update, restart, and verify:
sh bin/purchase-demo recover
# If diagnostics identify damaged/expired staging, explicitly rebuild TLS staging:
sh bin/purchase-demo recover --restart-staging
```

Normal failure releases the maintenance lock. A forced kill or host shutdown can leave the lock container behind. **First confirm no rotate/recover command is still running**, then:

```sh
sh bin/purchase-demo unlock --confirm-no-maintenance-running
sh bin/purchase-demo recover
```

Do not remove the pending marker manually or start operations on a mixed certificate set. Keep the same project name and volumes. Repeated maintenance commands are serialized; never run parallel raw init/rotation commands. The maintenance container is network-isolated and temporarily mounts every role's volume; normal services retain their separated mounts.

Ordinary stop/restart/update **does not use `down -v`**. That command is a deliberate, destructive full reset, not certificate renewal or recovery. Do not delete ledgers or use Docker prune. A fresh project name creates separate history rather than migrating existing purchases.

For an isolated verification stack, `PURCHASE_IMAGE` selects a unique image and `PURCHASE_UI_PORT` a free **loopback-only** host port (defaults: `ap2-purchase-demo:local`, `3100`). These do not change internal TLS hostnames.

## 2. Eight scenarios

The table gives the expected behavior, including the valid case. Scenario identifiers are stable in both languages; the selector displays translated labels.

| Scenario | Injected condition | What to observe |
| --- | --- | --- |
| `valid` | Three bags of tea for 2,400 JPY | Verification, acceptance, mock success and buyer verification of the authentic Success Receipt |
| `budget` | 3 × 1,200 JPY = 3,600 JPY | Payment issuance refused above the 3,000 JPY limit; payment not started |
| `quantity` | Only two bags offered against approval for three | Checkout issuance refused; payment not started |
| `tampered` | Checkout terminal signature altered | Seller rejects; payment not started |
| `error` | Simulated payment returns Error | An authentic Error Receipt is not purchase success; approval cannot be reused |
| `timeout` | Response delayed after saving the simulated result | Outcome unknown; refresh and recover the original ID; execution count stays 1 |
| `wrong_receipt` | Signed Receipt for a different payment ID delivered | Buyer does not accept success and does not pay again |
| `invalid_receipt` | Receipt signature damaged | Buyer does not accept success and does not pay again |

The screen never displays private keys, tokens or raw SD-JWT/JWS documents. Failure scenarios inject faults at specified boundaries; they do not replace the application's original protected order or saved Receipt.

Read all four stages. For example, `wrong_receipt` can have a successful simulated payment while buyer-side success remains unconfirmed. Error and unknown outcomes do not authorize another dispatch. The [historical validation record (English)](PURCHASE_VALIDATION.md) records the original eight-scenario coverage; [Localization](LOCALIZATION.md) describes checks for this bilingual change. Current-commit CI and reviews belong to the relevant pull request.

## 3. Replay, timeout and restart

### Retry the same purchase

Run the **same purchase ID** again after Success or Error is final. The buyer reuses the originally saved wire data. The seller looks up the existing acceptance record instead of starting another payment. Check that the simulated processor's execution count remains **1**. A newly approved purchase has a different ID and is not a replay test.

### Recover an unknown outcome

For `timeout`, the seller saves the simulated processor result, marks acceptance `unknown` and waits three seconds. The client's read timeout is two seconds. This intentionally causes a real response timeout across the network boundary.

- Use **Refresh status**, then **Recover the saved result** on the same purchase ID.
- Recovery reconciles the saved processor result and Receipt.
- It does not renew permission, issue a new Open, choose a different payment key or pay again.
- Do not stop at a mock-success notification; also check buyer-side Receipt verification.

### Restart buyer and seller

```sh
docker compose -f compose.purchase.yml restart buyer seller
```

Return to the purchase in the same browser session, then refresh or recover. Keys, approvals, original wire data, acceptance records and processor results remain in their named volumes. A2A Tasks use the standard MemoryStore and disappear on a process restart; purchase recovery uses a separate durable purchase ID.

### Stop and retain data

```sh
docker compose -f compose.purchase.yml down
```

Ordinary `down` keeps named volumes. The next `up` uses initialized data. Partial initialization or a missing database is not silently repaired with new keys or an empty ledger.

Run the following **only after deciding to discard all history and start over**. It deletes keys, approvals, ledgers, processor results and the session secret. Earlier purchases can no longer be recovered.

```sh
# Destructive full reset. Do not use for ordinary stop or restart.
docker compose -f compose.purchase.yml down -v
```

There is no need to `prune` shared Docker caches or remove other projects.

## 4. Three roles and their permissions

| Process | Secrets and state held | Can / cannot do |
| --- | --- | --- |
| authority | Issuer/Provider signing key, approval database, session secret, buyer/seller control tokens | Issues conditional Open after explicit approval and provisions both agents over protected control routes. Does not give the issuer key to the buyer. |
| buyer | Agent signing key, approval copy, first presentation wire data, seller A2A token, its own inbound control token | Creates Closed within approval and sends it to the seller's A2A endpoint. Cannot issue Open and has no seller control token. |
| seller | Merchant/synthetic-Receipt signing key, canonical order, challenge, acceptance ledger, processor results, inbound A2A/control tokens | Offers orders, verifies AP2, applies business rules, accepts once, simulates execution and issues Receipts. Has neither issuer nor Agent private keys. |

`authority-state`, `buyer-state` and `seller-state` are each mounted at `/state` only for their respective process. Only public keys and the CA certificate are shared at `/trust:ro` from `public-trust`. Only `init` has access to every volume for initial setup, and it exits without a network. The CA private key exists only in init's memory and is never saved.

`PURCHASE_STATE_DIR=/state` and `PURCHASE_TRUST_DIR=/trust` define these boundaries. Runtime processes are non-root, have a read-only filesystem and no capabilities, and are limited to 0.75 CPU, 384 MiB and 64 PIDs. Their state volume remains writable for database operations.

The [architecture diagram (Japanese labels)](images/purchase-architecture.svg) illustrates the same roles, keys, networks and storage boundaries described above.

## 5. Keep the four decisions separate

1. **AP2 verification:** verifies signatures, delegation, approval constraints, merchant order, challenge and Checkout/Payment binding.
2. **Application execution decision:** checks current protected approval, quantity, budget and order state; durable `authorize!` → `accept` → `start` controls single execution.
3. **Mock payment result:** saves the result in a separate durable processor record. Verification can succeed while payment fails. A timeout can occur after payment has succeeded.
4. **Receipt verification:** the buyer checks signature, issuer, payment ID and binding to the original Payment. An authentic Error is failure; a mismatched transaction or invalid signature leaves success unconfirmed.

Approval is saved before these four stages. Authority holds canonical approval data; seller holds the canonical order and challenge. They do not construct trust or the expected order solely from incoming claims.

## 6. Protocol and code map

Published dependencies are **`ap2_mandate_verifier = 1.6.0`** and **`a2a-rails = 0.3.0`**, using `Gemfile.purchase` and its lockfile. Neither SDK source overlays nor gem modifications are used.

- The AP2 reference is pinned to **v0.2.0, commit `b4587ac1d055888a73b4b21750973cffba961793`**. Synthetic results do not establish general AP2 conformance or evidence from a real issuer.
- Checkout uses `AP2MandateVerifier::ConditionalCheckout::PROFILE_REF` (`ap2.checkout.single_merchant_multi_item`). This scenario has one product, tea, while using the profile's quantity requirements.
- Payment uses `AP2MandateVerifier::Payment::PROFILE_REF` (`ap2.payment.single.complete.1`). SDK results such as `verified_research` retain their scoped meaning; they are not production certification or complete specification conformance.
- A2A uses **protocol 1.0**, JSON-RPC 2.0 envelopes and `A2A-Version: 1.0`. Gem version 0.3.0 does not mean A2A protocol 0.3.
- This **application-defined profile** uses a `SendMessage` text Part for a command, `message.metadata.purchase_demo` for AP2 payloads and a Task data Artifact for Hash results.
- a2a-rails 0.3.0 accepts text input and retains metadata. Formal AP2 DataPart input, Agent Card extension declaration and extension negotiation are not implemented. **This demo does not claim formal AP2 A2A extension support.**

| File | Responsibility and main APIs |
| --- | --- |
| `purchase_demo/authority_application.rb` / `authority.rb` | CSRF and browser-owned purchase-ID checks, explicit approval, protected provision/run/recover |
| `purchase_demo/protocol.rb` | `ConditionalCheckout.issue_open/issue_closed/present`, `Payment.issue_open/issue_closed/present/verify`, `InputBuilder.prepare/restore/inputs`, `PaymentReceipt.sign/verify` |
| `purchase_demo/buyer.rb` | Persists the exact first wire data; offer/purchase/status/recover and buyer-side Receipt verification |
| `purchase_demo/seller_application.rb` | Single `A2A::Rails::Agent` skill, `PurchaseHandler.call(message:, context:)`, separately authenticated `/control` |
| `purchase_demo/seller.rb` | `Runtime.seller.call(command,payload)`, `provision(payload)`, `PaymentAcceptance::Service` lookup/accept/start/finish/unknown/reconcile |
| `purchase_demo/store.rb` | Role-specific databases, unique purchase ID and processor key, SDK SQLite acceptance ledger |
| `purchase_demo/transport.rb` | Authority `request(service:,path:,payload:)`, buyer `a2a(command:,payload:)`, real HTTPS and JSON-RPC checks |
| `purchase_demo/setup.rb` / `compose.purchase.yml` | Disposable test keys, initial databases, separate processes, volumes and networks |

### TLS and SSRF boundaries

Puma terminates TLS directly on buyer and seller. The dedicated application client calls only fixed `https://buyer:3443` and `https://seller:3443` URLs and allowlisted routes; it never accepts an external URL. Agent Card endpoints must exactly match the fixed values.

TLS peer and hostname verification use the dedicated CA. Environment proxies, redirects and automatic retries are disabled. Requests and responses are limited to 128 KiB, JSON depth to 32, open/read/write timeouts to two seconds each and total time to eight seconds. Raw HTTP exceptions and response bodies are not returned to the UI.

This is a dedicated transport for two known Docker services, not a generic external-agent client. **It does not change a2a-rails production TLS/SSRF protection or use private reflection, allow-private settings or `VERIFY_NONE`.** Buyer and seller join only the internal `purchase` network and expose no host ports. Authority also joins a `ui` bridge to support Docker Desktop loopback publishing. Only `127.0.0.1:3100` is published. This is not a claim that authority cannot reach external networks.

## 7. Expiry and limits

- Open approval lasts **600 seconds**. A challenge lasts at most **300 seconds**, within approval expiry. Unexecuted purchases are rejected after expiry.
- Test TLS certificates last **seven days** from initialization. Expiry is enforced; use the explicit data-preserving TLS update above.
- Timeout or restart does not automatically extend approval or challenge validity. Looking up a consumed purchase does not authorize a new payment.
- Receipt comparison is limited to **24 hours from original approval issuance**. Recovery is not guaranteed indefinitely.
- If a process stops with a reserved acceptance record and no processor result, lookup is available but automatic redispatch is not. An explicit operational decision is required.
- The local simulated processor uses persistent records to aim for one execution. It does not guarantee distributed exactly-once execution with a real payment provider.
- Public trust is a synthetic registry. There is no real identity verification, KMS/HSM, issuer integration, CA operation, revocation, inventory or settlement.
- The loopback HTTP UI has no production login or TLS termination. **Do not expose it to the internet, forward its port or deploy it publicly.**

## 8. Verification and test commands

The original, pre-localization **2026-11-07** record used Apple Silicon / Docker Desktop 29.9.2 with native Linux ARM64. It reports **46 tests / 399 assertions**, plus live TLS, four concurrent A2A calls with one execution, timeout recovery and restart recovery. Desktop and 390 × 844 Chrome checks covered all eight scenarios. Standard/acceptance image regressions reported 11 tests / 221 assertions, eight wrappers and 68 matching gem files. These are **historical observations**, not results for this bilingual change or untested environments. See the [original validation ledger (English)](PURCHASE_VALIDATION.md), [localization guide](LOCALIZATION.md) and the relevant PR's Checks/reviews for current evidence.

The helper below checks a running stack, creates synthetic purchases and restarts buyer/seller. It does not delete volumes. It includes the live TLS boundary checks.

```sh
sh test/purchase_docker_validation.sh
```

After building the image, protocol and transport unit tests that need no keys or database can run in separate containers:

```sh
docker compose -f compose.purchase.yml build
docker compose -f compose.purchase.yml run --rm --no-deps authority \
  bundle exec ruby -Itest test/purchase_transport_test.rb
docker compose -f compose.purchase.yml run --rm --no-deps authority \
  bundle exec ruby -Itest test/purchase_protocol_test.rb
```

Run the live TLS boundary test from buyer against a running seller. It checks trusted CA/hostname, untrusted CA, wrong hostname, control-permission rejection, key separation and the production SSRF policy's rejection of private targets. A successful socket connection alone is not TLS-verification evidence.

```sh
docker compose -f compose.purchase.yml exec buyer \
  bundle exec ruby test/purchase_tls_boundaries.rb
```

`test/purchase_runtime_test.rb` uses a temporary directory and an in-process transport to test role integration. `test/purchase_setup_test.rb` covers missing files, empty databases, permissions and symlinks. They can run with the same container method but do not prove real TLS behavior. Browser checks should cover both languages, all eight results, ownership/CSRF, recovery, language persistence and desktop/mobile layouts. See [Localization](LOCALIZATION.md) for translation maintenance and legacy-data compatibility.

## 9. Application code versus future SDK improvements

This application implements the approval UI, role-specific key management, fixed transport, control provisioning, purchase IDs, protected orders/challenges, durable processor and Receipt lookup. These are not automatic SDK guarantees.

Possible future SDK work includes formal A2A structured input/extension declaration and negotiation, a public safe local-testing transport seam, simpler input building across profiles, typed acceptance/status/Receipt results, and clearer diagnostics for approval expiry and recovery. These are **not SDK features implemented by this change**; each requires separate compatibility and security review.
