# Docker portability / Docker対応環境 — published 1.6.0

## Contract / 対応範囲

The standalone SDK supports MRI 3.4.12 and 4.0.9 independently of Rails.
This optional Rails demo pins **MRI 4.0.9**, Rails components 8.0.4,
Bundler 4.0.20 and its existing checksummed frozen lockfile. Linux ARM64 and
AMD64 are the two Docker targets. No claim covers Rails on 3.4.12, native macOS
or Windows Ruby, other architectures, production Issuers or real payments.

SDK単体のMRI 3.4.12／4.0.9対応と、このRailsデモのMRI 4.0.9固定を区別します。
検証は合成データのみ。実Issuer信頼・購入認可・決済完了・本番運用の証明ではありません。
ARM64ネイティブとAMD64エミュレーションの結果を混同しません。

## Architecture fixes / 修正理由

Inspection found two ARM64-only inputs, rather than a dependency-version problem:

- Normal Dockerfile used the ARM64 **manifest**, not a multiarch index.
  Keep that exact existing digest for ARM64:
  `42c18f0c9807ba1349c0253617d7f08ef98b815463b2f7785d97c4efdfd80f4d`.
- Add official Ruby 4.0.9-trixie AMD64 manifest:
  `d1b33477de075536be34e1f50a15501c35151c380baba5e55a8c2b0b84ec9c7c`.
  It was resolved from official tag index
  `07042b74555ff2eef7365abd72d39cba6e499ab63e2d2942fd34d4778338495b`,
  whose source annotation identifies docker-library/ruby revision
  `566c0b5ecc3c1c5ce82ab5a94962cb02ceaba14b:4.0/trixie`.
  The current tag's ARM64 digest differs; it is deliberately **not** substituted.
- Acceptance image previously hardcoded `aarch64-linux-gnu` sqlite3 2.10.2.
  Select that or `x86_64-linux-gnu` according to Docker `TARGETARCH`, rejecting
  unsupported architectures. Version remains 2.10.2. SHA256s:
  - ARM64: `e9aea2c2b3476fc875dd8a89313a9a2862818519c0186bfb5b56d6f57bb08d98`
  - AMD64: `ca92731ab464df9cae503fa1a439a549e2724f6953c8c05a7769b59366e38f15`
  AMD64 hash source: [RubyGems version API](https://rubygems.org/api/v2/rubygems/sqlite3/versions/2.10.2.json?platform=x86_64-linux-gnu).

通常lockfileは既に両architectureの依存・checksumを含むため変更不要です。
SQLiteは追加imageだけに導入し、通常Bundler依存には追加しません。
上記は静的調査で判明した原因で、旧imageのAMD64失敗を実行したという主張ではありません。
歴史的candidate Dockerfileは変更・実行しません。

## Reproduce both targets / 両環境の完全再構築

Run from repository root. Select `arm64` on native ARM64, `amd64` on native x86_64.
Cross-architecture Docker Desktop runs are emulated, not native proof.
Builds need network access for official images and locked gems. `--no-cache`
reexecutes build steps; existing content-addressed base blobs can still be reused.
No host Ruby/Rails/SQLite installation and no host source-library overlay.

```sh
for arch in arm64 amd64; do
  docker build --no-cache --platform "linux/$arch" \
    -t "ap2-portability160-demo:$arch" .
  docker build --no-cache --platform "linux/$arch" \
    --build-arg "DEMO_BASE=ap2-portability160-demo:$arch" \
    -f Dockerfile.acceptance -t "ap2-portability160-acceptance:$arch" .
  docker run --rm --platform "linux/$arch" --network none \
    --cpus 1 --memory 512m --pids-limit 128 \
    "ap2-portability160-demo:$arch" timeout 900 sh test/docker_validation.sh normal
  docker run --rm --platform "linux/$arch" --network none \
    --cpus 1 --memory 512m --pids-limit 128 \
    "ap2-portability160-acceptance:$arch" timeout 600 sh test/docker_validation.sh acceptance
done
```

Execution prints OS, CPU, Ruby/RbConfig, archive identity and SQLite platform.
Every example/test also has a 120-second timeout. Normal validation checks all
three regression files and Checkout, Payment/Receipt, selective Checkout/Payment,
and policy wrappers. Acceptance checks recovery, long Open and twelve-month/budget
comparison. Containers are removed automatically; Docker images/cache remain.
Remove only these named task images when no longer needed; do not globally prune.

Both builds retain published Gem size **186,368 bytes**, SHA256
`62de85123e1379c538c9c4302b71a9c55c590162591169a4e335aaa03a8991f8`,
and all **68** archive/installed payload equality checks. The SDK is not rebuilt.
Execution also compares the current lockfile with the frozen installed copy.

## Native CI / ネイティブCI

`.github/workflows/docker-portability.yml` uses standard public Ubuntu 24.04
AMD64 and Ubuntu 24.04 ARM64 runners, asserts the host CPU, does not install QEMU,
and builds both image layers with `--no-cache`. Read-only repository permissions,
30-minute job limit and offline resource-bounded tests apply. It runs only on
relevant pull requests, not both push and PR, to avoid duplicate runs. No paid
larger runners. Actual run URLs/results must be read on the corresponding PR;
a workflow definition alone is not a native PASS.

## Observed / 実測

Local host: macOS 26.6.2 (25G83), Apple Silicon arm64. Docker Desktop server
29.9.2, Linux aarch64 VM, 8 CPUs / 8,215,117,824 bytes configured memory.
Builds run serially; execution limits are 1 CPU / 512 MiB / 128 pids.
Results are recorded below after completion. No native AMD64 local machine was used.

2026-11-06 UTC: native ARM64 no-cache normal and acceptance builds passed.
Both report Debian GNU/Linux 13 (trixie), MRI 4.0.9 revision `3e93b23afc`,
`aarch64-linux`; optional SQLite is 2.10.2 `aarch64-linux-gnu`.
Regression totals: 7/173 + 1/13 + 3/35 = **11 tests / 221 assertions**, no
failures, errors or skips. All listed wrappers and both 68-payload identity
checks passed. Long Open reserved 96,000 JPY across twelve mock starts.
The budget-only rejection retained 80,000 JPY / two reservations, no Ticket.

ARM64は両imageのno-cache再構築・11テスト221 assertions・全wrapperに合格。
12か月96,000円成功と予算超過拒否時80,000円／2件不変を確認しました。
AMD64 local emulation and native CI are pending in this initial implementation
record; do not treat them as PASS until the completion record/PR checks say so.
