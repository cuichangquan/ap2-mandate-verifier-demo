# 0.6.0複数明細候補のローカル検証

**以下は公開前の歴史記録です。** 公開済み0.6.0の通常起動は
[README](../README.md)、公開Gemを使う新たな実測は[PUBLISHED_060](PUBLISHED_060.md)を参照してください。
公開前snapshotのhash・失敗履歴は削除せず保持します。

2026-10-31 UTC。公開済み0.5.0の通常経路は保持し、新機能は
`Dockerfile.candidate` / `Gemfile.candidate` と `/multi-item` で明示選択する。
未公開候補の実装確認であり、公開・本番GO・実Issuer適合の証明ではない。

開始時デモmain: `1e3d5232e4b4c339df134db8e930126c1a0facb0`。
開始時本体main: `6ea21489c445dd6442be772b7e711f06fabcd8e8`。
下記はこれらに今回の作業差分を適用した未統合snapshotの観測で、最終候補の識別情報は本体の最終報告で別に固定する。

## 実装経路

- Coffee2個（単価120 cents）＋Tea3個（単価80 cents）＝USD480 cents。
- `CheckoutJWT.sign(profile_ref:)` → 合成Issuer/Agent envelope →
  `InputBuilder.trust(profile_ref:)` → prepare → 保存bytes → restore →
  現在の独立Host注文とverify → Evidence。
- 2件目だけTea2個にした真正署名入力は、合計金額400 centsが一致していても
  必須数量3個を満たさず `rejected / constraint_mismatch`、Evidenceなし。
- 正常検証後に、合成利用アプリのSuccess／Errorをそれぞれ
  `CheckoutReceipt.sign/verify(profile_ref:)` で確認。
  両方が真正性true、Errorの購入成功通知はfalse。
- 合成鍵は呼出しごとのメモリ内のみ。公開製品の発行API、nonce消費、注文更新、決済は追加しない。

新profileは `ap2.checkout.single_merchant_multi_item` v1。
旧profileは `ap2.checkout.single_merchant_sku` v1で保持する。
商品ID・要件ID・明細IDを区別し、要件IDと明細IDの一致を要求しない。
一般AP2への制約としてGem独自の上限を説明しない。

## 今回の実測

固定base: `ruby:4.0.9-trixie@sha256:42c18f0c9807ba1349c0253617d7f08ef98b815463b2f7785d97c4efdfd80f4d`。
Linux arm64、MRI4.0.9、Bundler4.0.20、OpenSSL library3.5.7。

| 確認 | 結果 |
| --- | --- |
| 公開0.5.0 image＋今回のデモsource、既存画面・CSRF・診断 | PASS: 7 tests / 173 assertions |
| 同公開image、既存Merchant署名とReceipt | PASS: 1 test / 13 assertions |
| 候補source overlay、複数明細service／Railsレスポンス | PASS: 3 tests / 31 assertions |
| 候補Dockerfile fresh build（`--no-cache --pull=false`） | PASS、通常Bundler install・固定依存lock |
| fresh候補imageの既存デモ試験 | PASS: 7 tests / 173 assertions |
| fresh候補imageのMerchant試験 | PASS: 1 test / 13 assertions |
| fresh候補imageの複数明細試験 | PASS: 3 tests / 31 assertions |

fresh buildの最初の試行は、依存未導入のbaseで `gem install --local` が
JWT不足を検出してFAIL。依存検査を省略せず、候補GemをBundler cacheに置き、
候補自身のSHA256をlockに設定して固定依存を通常導入する順序へ修正した。
再buildは成功。旧Gem checksumを新候補へ転用していない。

この時点のimageは `sha256:0f65e2d9b4b4f78a65e3a2a2e00d2f8cf6b04cd6468525b66741f4b8d09ef5de`、
内部の開発snapshot Gemは56,832 bytes、SHA256
`d97cdd46c8a76d922fb8999123be80ae274e7f42004bf96926bead5b286c45a7`。
本体sourceの後続修正により最終候補とは異なる場合がある。

試験は `--network none --cpus 1 --memory 512m --pids-limit 128`、各suite最大60–120秒。
fresh buildは公式Docker baseを再利用し、RubyGemsから固定依存を取得。
全通信量・build中のピークCPU/RSSは未測定。Mac本体への新規導入、共有cache削除、Web公開は行わない。
Dockerfile専用ignoreは対象の両repoだけをcontextに含め、.git・鍵・環境ファイル・vendor等を除く。

Rack::MockRequestによるRails画面生成・HTTP status・no-store・成功／不足／Receipt表示を確認。
実ブラウザ観測は親作業の最終記録と区別する。過去の0.5.0画像・件数は今回の複数明細実測として数えない。
