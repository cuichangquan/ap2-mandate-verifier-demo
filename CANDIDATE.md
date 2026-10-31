# Historical 0.3.0 candidate record

This document preserves observations and the withdrawn archive record from before
publication. It is **historical**, not the current startup guide. The published
0.4.0 workflow is now the default; use [README](README.md). Candidate opt-in code,
Dockerfile and separate lockfiles have been removed. To inspect the old setup,
use [the pre-publication source](https://github.com/cuichangquan/ap2-mandate-verifier-demo/tree/65416f7de9d83cddc3557b4c5ed51dcd7c0cdc6e).

# Pre-publication observations

The earlier archive SHA256 `5de6907cfcf0565ddaba1385b1d38ae113cc5e26d52259d769030237378a48a8`
is **withdrawn** because InputBuilder.verify leaked exceptions on assembly failure.
The corrected local archive remains version0.3.0 and37,376bytes but has SHA256
`b3a31d5a8b0718f1085745dd4d97d85f210ff9a1628798110da9ff382ae546bd`.
The candidate lock is pinned to this replacement. Do not use the old archive or
its earlier observation below as evidence for the replacement. Correction PR:
https://github.com/cuichangquan/ap2-mandate-verifier/pull/219.

This branch is a local, unpublished candidate. The ordinary Dockerfile, Gemfile
and lock continue to select published **0.2.1**. The builder path is enabled only
by `INPUT_BUILDER_CANDIDATE=1`, set by `Dockerfile.candidate`.
No public Web deployment or RubyGems publication is performed.

Place the final checked `ap2_mandate_verifier-0.3.0.gem` in ignored `candidate/`.
Use its final SHA256 from the release-candidate record, not a guessed value:

```sh
docker build --platform linux/arm64 -f Dockerfile.candidate \
  --build-arg CANDIDATE_SHA256=FINAL_CHECKED_SHA256 \
  -t ap2-input-builder-demo:candidate .
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-input-builder-demo:candidate timeout 300 bundle exec ruby test/demo_test.rb
docker run --rm --name ap2-input-builder-demo-candidate \
  --cpus 1 --memory 512m --pids-limit 128 -p 127.0.0.1:3100:3000 \
  ap2-input-builder-demo:candidate \
  timeout 3600 bundle exec puma -b tcp://0.0.0.0:3000 -t 1:1 config.ru
```

Visit http://127.0.0.1:3100/ and select normal, tampered, expired. The candidate
banner distinguishes the route. Expected real Gem outputs remain:

| Scenario | status / code | Evidence |
| --- | --- | --- |
| 正常 | verified_research / scoped_research_verified | present |
| 改ざん | rejected / host_binding_mismatch | absent |
| 期限切れ | rejected / invalid_purchase_time | absent |

`InputBuilderScenarioVerifier` reads explicit synthetic order and registration
files plus original signed Strings from `fixtures/input_builder/`. It calls
trust → prepare → saves a detached String → restore → reads current state → verify.
Only the signed Checkout is modified for the tampered case; the saved issued
Challenge remains unchanged. The fixed clock controls the expiry case.
A production app must supply actual authenticated persistence and atomically
issue/consume nonce; the demo does neither and makes no purchase decision.

The legacy full fixture remains for the ordinary published-Gem route. Neither
route learns trusted keys or expected order values from received signed claims.
The original fixture attribution applies; see `fixtures/input_builder/NOTICE.md`.

Candidate-specific test/browser results are recorded separately at release
preparation. Historical README test results are not evidence for this candidate.
After publication, switch normal dependency, lock and archive identity together
under a reviewed change. Do not merge an unavailable dependency into normal main.

## Historical withdrawn candidate observation (2026-10-31)

Built the candidate Dockerfile on Linux arm64 using the exact locally built
0.3.0 Gem: **37,376 bytes**, SHA256
`5de6907cfcf0565ddaba1385b1d38ae113cc5e26d52259d769030237378a48a8`.
The candidate lock checksum is fixed to these bytes; update it only when a new
candidate is independently checked. Product source is merged main
`016a030815b393f42ff89e7d285a4bc1cc46e375` (PR218).

Fresh candidate build succeeded with the existing fixed base layers and ordinary
Bundler dependency resolution. The first build stopped because an overly broad
version substitution had corrupted an unrelated checksum; the lock was recreated
from stable lock and only the two package versions and candidate checksum changed.
No dependency checks were weakened. The preliminary resource flag mismatch stopped
before build. Final tests: **4 tests /85 assertions /0 failures /0 errors**.
The additional test rejects any read of legacy full.json while all3 cases execute.
Actual localhost browser forms confirmed normal/scoped_research_verified/Evidence,
tampered/host_binding_mismatch/no Evidence and expired/invalid_purchase_time/no
Evidence, with the0.3.0 candidate banner. No mocks or public deployment.

Build RUN limits2CPU/2GiB; tests/preview1CPU/512MiB/PIDs128. Tests network-none
and300-second timeout; preview bound127.0.0.1 with one Puma thread. Docker daemon
shared-layer work is outside RUN limits. Total network traffic and peak resource
use were not measured; these are bounded functional observations, not performance
or supply-chain guarantees. Normal published0.2.1 files remain unchanged.

## Corrected replacement observation

Product source `877f59195632f74714a60551b6afb22ac81d93e3` (correction PR219),
37,376-byte archive SHA256
`b3a31d5a8b0718f1085745dd4d97d85f210ff9a1628798110da9ff382ae546bd`.
This replaces the withdrawn archive above; version remains0.3.0 because neither
candidate was published. Candidate lock pins the replacement bytes.

Rebuilt with the corrected Gem and ordinary frozen Bundler install. Tests now
pass **5 tests /90 assertions /0 failures /0 errors**, including a real public
InputBuilder.verify malformed-argument check returning registered failure Result,
not an exception. Actual localhost browser repeated all3 scenarios and confirmed
normal/scoped_research_verified/Evidence, tampered/host_binding_mismatch/no Evidence,
and expired/invalid_purchase_time/no Evidence. These are fresh replacement results,
not a reuse of the withdrawn candidate's PASS. Same bounded build/test/preview
settings as above; no external Web deployment or publication.

The product fix additionally retains provider/dependency unavailability separately
from malformed inputs and checks selector shapes before dereferencing them.
Normal published0.2.1 Gemfile/lock/Dockerfile remain unchanged. GitHub and local
independent review evidence for the corrective candidate is recorded with PR219.
