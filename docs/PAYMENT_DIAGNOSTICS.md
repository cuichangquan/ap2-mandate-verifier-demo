# Payment diagnostics: current result → Ruby call

[日本語](PAYMENT_DIAGNOSTICS.ja.md)

This is Issue #35 **A3**, not a repeat of completed A1 (integration/recovery examples)
or A2 (readiness/TLS maintenance). The four stages remain separate: AP2 verification,
application execution decision, mock payment and Receipt verification.

The result page keeps existing reason/status codes and adds optional catalog diagnostics:
operation, stage, reason, field and English/Japanese checks. Each links to an inert,
abbreviated Ruby example matching `seller.rb`, `buyer.rb` and `protocol.rb`. Expanding
code, changing language or reloading cached history does not execute, recover or query
a purchase. The normal published 1.6.0 route and old saved results have no new diagnostics;
that is not success or failure evidence. The complete call map labels candidate-only APIs.

## Facts versus application advice

`Payment.verify(**inputs).diagnostic` explains a confirmed check, not a root cause.
`Service#accept`, `lookup`, `finish` and `reconcile` results can carry diagnostics.
The candidate path calls `start_with_diagnostic` **once**, reads `.execution` and
`.diagnostic`; the published fallback calls legacy `start` **once**. Neither path
replays verification or execution just to produce a display.

```ruby
started = service.start_with_diagnostic(ticket: accepted.ticket,
  verification_inputs: verification(fresh, wires))
execution = started.execution # Execution or nil, never retry permission
checked = AP2MandateVerifier::PaymentReceipt.verify(jwt: receipt,
  closed_sd_jwt: saved_closed, **trusted_context, verified_at: now)
checked.verified?          # authenticity + references
checked.payment_succeeded? # a genuine Error is verified, but not success
checked.diagnostic        # may be nil; not permission to pay
```

These snippets omit host trust acquisition, durable store creation, saved challenge,
current order/clock, error handling and mock-processor code. See actual role methods.
Only catalog identities are stored/transmitted; arbitrary hint text, unknown identifiers,
exception messages and input values are dropped. Display rehydrates hints from the
installed Gem catalog. Losing a diagnostic never changes existing status decisions.
A timeout is an application observation; it is **not** relabeled as a Gem-diagnosed cause.
Unknown outcomes, nil execution and genuine Error do not authorize retry or capacity release.

## Candidate package route (not the normal demo)

Keep the reviewed candidate package, exact source commit, version, byte count and SHA256
from the core candidate report together. Never substitute a rebuild without revalidating.

1. Build the ordinary image with `docker build -f Dockerfile.purchase -t ap2-purchase-demo:local .`.
2. Place the exact candidate at `candidate/payment-diagnostics.gem` (gitignored).
3. Build the overlay (replace the three placeholders with the recorded candidate values):

```sh
docker build -f Dockerfile.payment-diagnostics \
  --build-arg CANDIDATE_VERSION='<version>' \
  --build-arg CANDIDATE_BYTES='<bytes>' \
  --build-arg CANDIDATE_SHA256='<sha256>' \
  -t ap2-purchase-diagnostics:candidate .
```

The overlay checks bytes/hash/name/version, installs that `.gem`, adjusts **only its
own** Gemfile/lock version and checks frozen dependencies and installed feature paths.
Dependency changes are not silently resolved; if necessary update the reviewed overlay.
Normal repository Gemfiles, lockfiles and published checksums remain untouched.
Use a fresh Compose project and `--no-build`, not existing purchase state:

```sh
COMPOSE_PROJECT_NAME=payment-diagnostics-qa PURCHASE_UI_PORT=3117 \
  PAYMENT_DIAGNOSTICS_IMAGE=ap2-purchase-diagnostics:candidate docker compose \
  -f compose.purchase.yml -f compose.payment-diagnostics.yml up -d --no-build
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-purchase-diagnostics:candidate timeout 120 bundle exec ruby \
  test/purchase_diagnostics_runtime_test.rb -n /test_diagnostics_/
```

Run the normal published CI separately. Record exact candidate and demo commit, native
architecture, Ruby version, test results and anything not run. In-process role tests do
not prove HTTPS, browser visual layout or native ARM64 portability.

## After owner-approved publication

Do not publish or switch normal dependencies in this PR. Verify the downloaded public
Gem SHA256 matches the reviewed candidate, then prepare a separate reviewed change to:
`Gemfile`, `Gemfile.lock`, `Gemfile.purchase`, `Gemfile.purchase.lock`, `Dockerfile`,
`Dockerfile.purchase`, installed-Gem checks and current README/Quick Start version claims.
Update AP2 package byte/hash guards to the **verified public bytes**; preserve historical
candidate and evidence files explicitly as history. Re-run normal native ARM64/AMD64 CI
and HTTPS scenarios against the public installed Gem before merging that switch.
No tag, GitHub Release, deployment or ordinary dependency switch is performed here.

Use a unique image tag via `PAYMENT_DIAGNOSTICS_IMAGE` and a free `PURCHASE_UI_PORT` (example: 3117) for parallel QA. Do not stop or replace an existing stack.
