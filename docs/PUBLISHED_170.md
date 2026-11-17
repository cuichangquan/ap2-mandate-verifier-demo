# Public 1.7.0 package switch / 公開版1.7.0への切替

## Package identity / 配布物

- Public download: https://rubygems.org/downloads/ap2_mandate_verifier-1.7.0.gem
- Fresh download verified: 2026-11-17 23:42:13 UTC.
- Size: **208,384 bytes**; **75** archive payload files.
- SHA256: `2a3da0706313fd6ef6bf05dd0aed2f05899a5690b42568b3ebd814b41ad17140`.
- These bytes match the previously reviewed 1.7.0 candidate. The public archive was
  downloaded and installed, not rebuilt or loaded from a source checkout.
- Switch base: demo PR #39 head `295d64ef4bf6390eae3c581141f90b33bbd97690`.

公開配布物を新規取得し、別のGem保存先へ実際にインストールしました。配布物と
インストール済み75ファイル、版、依存関係、Ruby要件、source外からの読み込み、
診断APIの存在を確認しています。過去の1.6.0記録は履歴として残します。

## Local verification / ローカル検証

Cloud Linux x86_64, Ruby **3.4.12**, exact installed public Gem **1.7.0**:

- Installed archive audit: PASS, 75 payloads match.
- Diagnostic projection unit tests: 5 tests / 17 assertions, PASS.
- Diagnostic runtime flows: 4 tests / 26 assertions, PASS.
- Exact public projection/nonleak test: 1 test / 44 assertions, PASS.
- Diagnostic English/Japanese Rack UI: 5 tests / 113 assertions, PASS.
- Existing locale/Rack suite: 45 tests / 4,015 assertions, PASS (includes inherited tests).
- All eight current published Ruby examples: PASS.
- No skipped tests in these runs.
- Both lockfiles are byte-identical outside AP2 version/checksum lines.
- Both locale JSON files parse; shell syntax and whitespace checks pass.

The Rack tests used a temporary local-only dependency resolution with Rails 8.1.4.1
and Minitest 5.25.4. This is **not** the repository's frozen Ruby 4.0.9 / Minitest 5.27.0
Docker stack. No repository lockfile was regenerated for this local environment.

## Remaining gates / 残る検証

At preparation time, the exact switch commit's native ARM64/AMD64 Docker CI,
HTTPS stack and browser visual verification are **NOT_RUN**. Check PR #39 for
subsequent exact-head results. A prior draft/candidate CI pass is not evidence that
this public-package switch passed. The ordinary purchase lane now runs the four
diagnostic runtime cases and both ordinary images require the diagnostic API as
part of the exact installed archive audit, preventing a silent capability skip.

この差分のnative ARM64/AMD64・固定Docker環境・HTTPS・実ブラウザは作成時点で未実施です。
PR #39の当該HEADの結果を確認してください。通常購入CIに4件の診断実行試験を含め、
通常イメージ2種でAPIの存在を必須検査します。既存起動スタックや保存データの置換、
マージ、Gem再公開、タグ、GitHub Release、デプロイはこの切替作業では行っていません。
