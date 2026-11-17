# Payment diagnostics: current result → Ruby call

The post-publication normal path uses 1.7.0. The candidate-only Dockerfile and recipe below are historical reproduction instructions for pre-publication commit `e3fbb0eba4891ad7bb74112fdd3a0dafa18aed55`. Use a separate checkout of that commit to reproduce them, not the normal 1.7.0 base image. The current switch and its verification limits are recorded below; publication and deployment remain separate actions.

[日本語](PAYMENT_DIAGNOSTICS.ja.md)

This is Issue #35 **A3**, not a repeat of completed A1 (integration/recovery examples)
or A2 (readiness/TLS maintenance). The four stages remain separate: AP2 verification,
application execution decision, mock payment and Receipt verification.

The result page keeps existing reason/status codes and adds optional catalog diagnostics:
operation, stage, reason, field and English/Japanese checks. Each links to an inert,
abbreviated Ruby example matching `seller.rb`, `buyer.rb` and `protocol.rb`. Expanding
code, changing language or reloading cached history does not execute, recover or query
a purchase. The normal published 1.7.0 path exposes diagnostics. Older 1.6.0 saved results may lack them;
absence is not success or failure evidence.

## Facts versus application advice

`Payment.verify(**inputs).diagnostic` explains a confirmed check, not a root cause.
`Service#accept`, `lookup`, `finish` and `reconcile` results can carry diagnostics.
The published 1.7.0 path calls `start_with_diagnostic` **once**, reads `.execution` and
`.diagnostic`; compatibility with older Gems uses legacy `start` **once**. Neither path
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

## Historical candidate package route (pre-publication checkout only)

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

## Published 1.7.0 switch

The owner-approved switch updates the two ordinary Gemfiles/lockfiles, Dockerfiles,
installed-package audit, published examples and current English/Japanese instructions.
The exact public archive is 208,384 bytes, SHA256
`2a3da0706313fd6ef6bf05dd0aed2f05899a5690b42568b3ebd814b41ad17140`,
matching the reviewed candidate. Both ordinary images verify this archive and compare
all 75 installed payloads; no source checkout or rebuild substitutes for installation.
Historical candidate files and evidence remain unchanged.

The existing native ARM64/AMD64 CI must pass for the exact switch commit before merge.
It exercises the installed public Gem, diagnostics, English/Japanese UI and HTTPS
purchase/recovery flows. Current CI results belong to PR #39, not the old candidate
record. Updating the draft does not merge or deploy it and does not replace a running
stack. Tags, GitHub Release and publication are not performed by this demo change.
