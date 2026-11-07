# AP2 Ruby SDK 1.6.0 — local learning demo

[English walkthrough](docs/QUICK_START.md) · [SDK日本語README](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/README.ja.md)

公開Gem **ap2_mandate_verifier 1.6.0**を使い、Checkout・Payment・Receiptの関係を試すローカルデモです。
**すべて合成データで、本番決済は扱いません。検証成功と決済成功は別です。**
SDK自体はRails非依存です。このリポジトリの画面だけがRailsを使います。

## 別プロセスの購入Agent × 販売Agentデモ

[購入デモの起動・設計・検証手順](docs/PURCHASE_DEMO.md)では、明示承認→AP2検証→永続受理→模擬決済→購入側Receipt確認を、独立したbuyer/sellerのHTTPS通信で試せます。公開Gem `ap2_mandate_verifier 1.6.0` / `a2a-rails 0.3.0`を使い、SDKの変更や実決済はありません。既存例とは別のCompose構成です。Apple SiliconのDockerで46 tests / 399 assertionsと実TLS・再起動復旧を確認済みです。実Chromeのdesktop/mobileで全八ケースも確認済みです。最終commitのCI・レビュー・統合結果は対応するPRを参照してください。[検証範囲](docs/PURCHASE_VALIDATION.md)を確認してください。

```sh
export COMPOSE_PROJECT_NAME=ap2-purchase-demo
docker compose -f compose.purchase.yml up --build
```

http://127.0.0.1:3100/ で正常系を選び、明示承認してから実行します。以降のrestart/downも同じプロジェクト名で行います。既存単体デモと同じ3100番を使うので同時起動しないでください。

## 初めての方へ：試す順序

1. 下のDocker手順でimageを用意し、画面の正常・改ざん・期限切れ・入力不足を比較します。
2. `/merchant`で真正なSuccess／Error Receipt、`/multi-item`で数量不足の拒否を比較します。
3. 同じimageでRubyのCheckout発行→提示→検証、Payment→Receiptを実行します。
4. 任意のSQLite追加imageで、12か月の長期Openと累計予算超過を比較します。

| 体験 | 実行方法 | 見るポイント |
| --- | --- | --- |
| 条件付きCheckout発行・提示・検証 | `examples/checkout.rb`（下記） | Open→Agent Closed→Evidence、成功／拒否Receipt |
| Direct／条件付きPayment | `examples/payment.rb` | Checkout結合とPayment Receipt、真正性と通知結果の違い |
| 選択的Checkout＋Payment | `examples/selective_checkout.rb` | 保持する完全Openと送信する候補の差、必須条件は維持 |
| 長期Open | `examples/long_payment_limits.rb`（追加image） | 12か月96,000円、別承認の3月は予算超過で拒否 |

画面は既存のCheckout検証用です。Paymentや長期OpenはRuby単体例で体験します。
本人認証・同意UI・Provider鍵管理・最新信頼情報・注文／Challenge・永続単発利用管理はアプリ側の責任です。
SDKは実決済を実行せず、Receiptもアプリが通知した結果を認証するものです。

## Dockerで起動

GitとDockerを用意してください。Linux ARM64／AMD64用の固定imageを選択できます。ローカルARM64はネイティブ、Apple Silicon上のAMD64はエミュレーションです。[対応環境・再構築手順](docs/DOCKER_PORTABILITY_160.md)を確認してください。DB・Redis・ホストへのRuby導入、環境変数や候補Gemfileの指定は不要です。

```sh
git clone https://github.com/cuichangquan/ap2-mandate-verifier-demo.git
cd ap2-mandate-verifier-demo
docker build --platform linux/arm64 -t ap2-mandate-verifier-demo:local .
docker run --rm --name ap2-mandate-verifier-demo \
  --cpus 1 --memory 512m --pids-limit 128 -p 127.0.0.1:3100:3000 \
  ap2-mandate-verifier-demo:local \
  timeout 3600 bundle exec puma -b tcp://0.0.0.0:3000 -t 1:1 config.ru
```

http://127.0.0.1:3100/ で従来の4検証ケースを選びます。「販売者署名と成功・拒否Receipt」と「複数商品・数量」のリンクから、各APIの結果を比較できます。画面の1.6.0・status/code・診断・Evidence・Receiptの真正性と業務結果を確認してください。終了は `docker stop ap2-mandate-verifier-demo`。Web公開や共有cacheのpruneは行いません。

| ケース | 結果 |
| --- | --- |
| 正常 | verified_research / scoped_research_verified、Evidenceあり |
| 購入内容を改ざん | rejected / host_binding_mismatch、Evidenceなし |
| 期限切れ | rejected / invalid_purchase_time、Evidenceなし |
| 通貨を渡し忘れる | rejected / invalid_host_context、order.currency診断、Evidenceなし |
| Merchant署名・Success Receipt | 真正性true、購入成功通知true |
| Merchant署名・Error Receipt | 真正性true、購入成功通知false、拒否通知true |
| Coffee2個＋Tea3個 | 明示的な複数明細profileで検証成功、Evidenceあり |
| 2件目をTea2個へ減らす | 真正署名・金額一致でも constraint_mismatch、Evidenceなし |

## RubyだけでCheckout → Payment（通常image）

```sh
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-mandate-verifier-demo:local timeout 120 bundle exec ruby examples/checkout.rb
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-mandate-verifier-demo:local timeout 120 bundle exec ruby examples/payment.rb
```

Checkoutは`verified=true; rows=3; requirements=2`と両Receipt、Paymentは
`Direct and conditional Payment: verified`と両Payment Receiptを表示します。
真正なErrorでも`authentic=true`ですが、成功通知はfalseです。原文・秘密鍵は表示しません。

## 12か月と累計予算超過（任意の追加image）

```sh
docker build --platform linux/arm64 -f Dockerfile.acceptance -t ap2-acceptance:local .
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-acceptance:local timeout 120 ruby examples/long_payment_limits.rb
```

固定SQLite driverだけを追加し、通常Gemfileは変更しません。12か月を合成時計で進めるため待機やschedulerは不要です。
最初は同じOpen pairで毎月8,000円、12回・96,000円を100,000円以内で予約し、模擬開始と元Receipt復旧を確認します。
続く別承認では1月40,000円→2月80,000円→3月拒否となります。
3月の署名データは有効でも、合計120,000円が予算を超えるためTicketは出ず、予約は80,000円のままです。
予約は決済完了ではなく、比較ケースはprocessorを開始しません。一時DBは終了時に削除します。

長期OpenのUTC月次JPY profileは**AP2汎用MONTHLY仕様への完全準拠ではありません**。
content最大400日でも提示証明は短命です。選択的開示・PISP／日時との合成、日次分割・catch-up・自動枠返却は対象外。
[詳細・配布物の検証記録](docs/PUBLISHED_160.md)、[SDK契約](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/LONG_PAYMENT.md)。

## 複数商品・数量

http://127.0.0.1:3100/multi-item はCoffee2個＋Tea3個の成功と、Tea2個だけの不足を比較します。真正なSuccess／Error Receiptも表示し、Errorでも署名検証はtrue、購入成功通知はfalseになります。

ページは入力構築・prepare・保存・restore・現在状態のverify・Checkout署名・Receipt署名と検証を公開APIで実行します。Issuer／Agent envelopeはデモ内の合成試験処理で、製品発行APIではありません。

明示profileは `ap2.checkout.single_merchant_multi_item` v1です。最大8明細・8要件・各8候補、商品IDで数量を完全割当てし、要件IDと明細IDは別です。同じ商品の複数行を保持し、候補の重なりを支持し、余剰・不足・二重充当を拒否します。旧 `ap2.checkout.single_merchant_sku` v1は通常4ケースで引き続き利用し、定義と受理範囲は変えていません。

税／送料／割引・複数販売者・実決済は対象外です。[複数明細契約](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/MULTI_ITEM_CHECKOUT.md)、[公式Python SDKとの差異](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/MULTI_ITEM_INTEROP.md)、[今回の公開Gem検証](docs/PUBLISHED_160.md)を参照してください。

**EvidenceもReceipt真正性も購入・決済の実行許可ではありません。** 業務結果はアプリが明示し、実決済・注文更新・nonce消費は行いません。すべて合成データ・メモリ内テスト鍵で、実Issuerの信頼を示しません。固定時計は1800000000、期限切れケースは1800000101です。

## テスト

```sh
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-mandate-verifier-demo:local sh -c \
  'timeout 120 bundle exec ruby test/demo_test.rb && timeout 60 bundle exec ruby test/merchant_scenario_test.rb && timeout 60 bundle exec ruby test/multi_item_scenario_test.rb'
```

両architectureのno-cache手順と実測範囲は[Docker検証記録](docs/DOCKER_PORTABILITY_160.md)、公開1.6.0の従来実測結果は[公開Gem検証記録](docs/PUBLISHED_160.md)へ記録します。過去の候補試験を今回のPASSとして数えません。

## 固定構成・責任境界

MRI4.0.9、Bundler4.0.20、railties/actionpack8.0.4、Puma6.6.1、Minitest5.27.0。Docker baseはarchitecture別の公式Ruby digestに固定しています（既存ARM64 digestは維持）。Verifier1.6.0とJSON2.19.9／JWT3.3.0／base640.3.0／OpenSSL gem4.0.2／Digest3.2.1を使用します。

Dockerfileは公式Gemの **186,368 bytes** とSHA256 `62de85123e1379c538c9c4302b71a9c55c590162591169a4e335aaa03a8991f8` を導入前に照合し、同じbytesをBundler cacheへ渡します。通常導入後も全68ファイルのarchive/installed一致、依存・Ruby要件、source外からのロードを検査します。Gemは再buildしません。正式リリースsourceは [`964e572`](https://github.com/cuichangquan/ap2-mandate-verifier/tree/964e572dc16d886561293cf90ddb9e2c927346bf)。レビュー済み候補source `98f7325a9dd0ee06739fe95e1306abe9b1c6ee5d` と同一tree `c9a9faaec045a9854fded3c1b4db375332a5fa57` です。取得／provider／依存の失敗時は停止し、lockやchecksumを緩めません。

`ScenarioVerifier` は独立した業務情報と署名原文からprepare→保存→restore→現在状態→verifyを行います。保存したB／digestを現在値へ修復せず、利用者入力から鍵・期待注文を推測しません。

[対応契約](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/SUPPORT_CONTRACT.md)／[Merchant API・仕様とSDK差異](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/MERCHANT_SIGNING.md)／[過去の候補・実測履歴](docs/HISTORY.md)。実Issuer・Host本番・原子的nonce消費・失効・性能・Web運用等のHOLDは維持します。RailsデモはMRI4.0.9固定です。SDK単体のMRI3.4.12／4.0.9対応と区別し、他OSやデモのRuby3.4.12は未検証です。[MIT](LICENSE)、[出所通知](THIRD_PARTY_NOTICES.md)、[業務fixture通知](fixtures/input_builder/NOTICE.md)を保持します。実行ログ・依存archive・一時セッション鍵はコミットしません。

## 開発source比較用の候補手順

通常利用は上記Dockerfileだけで完結します。`Dockerfile.candidate`／`Gemfile.candidate` はローカルsourceの比較用として別経路に残しています。公開Gemと同じversion表示でもそのbuild物は公開bytesの証明にならず、公開Gemの代用にしません。この公開後整備では候補Gemをbuildしません。

この比較経路は歴史的な0.6.0 source用です。`Gemfile.candidate.lock`を専用に使い、
1.6.0の通常起動lockと混ぜません。現行1.6.0 sourceの候補build手順ではありません。

過去の候補起動・試験は[0.6.0候補の歴史記録](docs/MULTI_ITEM_CANDIDATE.md)へ、さらに古い候補は[CANDIDATE.md](CANDIDATE.md)へ残しています。

![歴史記録：公式0.5.0による成功・拒否Receiptの実画面](docs/images/merchant050.jpg)

## Direct購入側API（0.7.0から継続）

1.0.0は`CheckoutJWT.verify`、`Buyer.issue_closed/present_closed/verify`と
Direct Receipt profileを公開しています。[承認→発行→提示→販売者検証→Receipt確認の完全実行例](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/examples/direct_checkout.rb)と
[API契約](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/BUYER_DIRECT_CHECKOUT.md)を参照してください。
1販売者・1〜8明細・複数商品に対応します。

このRails画面は既存のOpen→Agent Closed検証と販売者署名／Receiptの合成シナリオを維持しています。
Directの本人認証・承認UI・Provider鍵管理を実装した画面ではありません。
本人認証・購買権限・保護された承認記録・永続一意制約／原子処理・結果不明時の照会は利用アプリの責任です。
Gem検証やデモ受理は実購入・実決済成功を意味しません。

## Published Payment example

```sh
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-mandate-verifier-demo:local timeout 120 bundle exec ruby examples/payment.rb
```

Direct／条件付きPaymentと両Receipt結果を模擬します。署名検証は実決済の成功や最終実行許可ではありません。

## Published selective Payment example

```sh
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-mandate-verifier-demo:local timeout 120 bundle exec ruby examples/selective_payment.rb
```

公開Gemの同梱例を使い、機密保持する5disclosuresと送信する3disclosuresを比較し、選択Paymentと両Receipt結果を検証します。非選択値・salt・full wireは出力しません。候補数・順序・issuerJWTのリンク可能性までは隠しません。

## Published selective Checkout + Payment example

```sh
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-mandate-verifier-demo:local timeout 120 bundle exec ruby examples/selective_checkout.rb
```

公開1.6.0の同梱例を使い、販売者・商品候補を絞ったCheckoutとPaymentを続けて検証します。全要件・数量は残り、独立Host入力・原文hash・両Receipt結果まで確認します。販売者と商品候補は独立した許可集合で、相関条件を保証しません。最終購入許可・永続nonce消費・注文現在性・失効・実決済はアプリ責任です。

## Published PISP + execution-date example

```sh
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-mandate-verifier-demo:local timeout 120 bundle exec ruby examples/payment_policy.rb
```

明示profileでDirect・条件付き・選択的Paymentを試します。署名されたPISPと日時を独立したアプリの信頼済み実行予定と照合し、日時窓の包含境界をUTC瞬間として比較します。旧profileの意味は変わりません。これはQWAC認証、実行予約、実決済や精算の証明ではありません。

## Published Payment acceptance example

通常imageを上記手順で用意した後、任意のSQLite driverだけを追加するARM64例です。SDKの基礎依存と通常Railsのlockは変えません。

```sh
docker build --platform linux/arm64 -f Dockerfile.acceptance -t ap2-acceptance:local .
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-acceptance:local timeout 120 ruby examples/payment_acceptance.rb
```

機密のproofを出力せず、初回予約、再署名再送、開始CAS、模擬dispatch一回、unknown保存、同じDBの再open、遅延Receipt復旧を比較します。例のDBは合成一時DBです。本番では全worker共通の保護された永続DBと独立した承認occurrenceが必要で、起動時のDB再作成・任意UUID・timeoutを新しい実行許可に使いません。PSP照会・冪等性、障害復旧、実決済のexactly-onceは保証しません。
