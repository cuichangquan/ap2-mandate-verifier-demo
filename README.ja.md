[English](README.md) | [日本語](README.ja.md)

# AP2 Ruby SDK 1.6.0: ローカル学習デモ

公開Gem **ap2_mandate_verifier 1.6.0**で、署名付き購入承認、Checkout・Payment Mandate、Receiptを試します。ブラウザ画面とRubyの例を通じて、Agentに許された購入内容、販売者による権限の検証、購入側による結果確認を学べます。

**データ・鍵・決済処理はすべて合成です。実際のお金は動きません。検証成功と決済成功は別です。** SDKはフレームワーク非依存で、このリポジトリのブラウザ画面だけがRailsを使います。

ここではAP2の署名付き購入・支払文書を扱います。別構成の購入デモでは、Agent間の通信にA2Aを使います。どちらのプロトコルも事前知識は不要です。外部LLM、決済口座、Issuerのアカウントも必要ありません。

## 最初に試すデモを選ぶ

| デモ | 試すこと | 観察すること |
| --- | --- | --- |
| 通常のブラウザデモ、ポート **3000** | 正常・改ざん・期限切れ・通貨不足、販売者署名、複数商品と数量 | 検証状態、診断コード、Evidence、真正なSuccess／Error Receipt |
| A2A × AP2購入デモ、ポート **3100** | 明示承認、Agent実行、八つのシナリオ、状態更新、復旧、履歴 | AP2検証、アプリの実行判断、模擬決済、購入側Receipt確認の四段階 |
| オフラインのRuby例 | Checkout → Payment、選択的開示、実行条件、永続受理、長期Open | SDKの公開APIと、それを利用するアプリの責任 |

どちらの画面も初回は **English** です。画面上部の **English / 日本語** で切り替えられます。選択した言語は画面遷移・フォーム送信・リダイレクト・再読み込みでも維持されます。未対応の言語指定は英語に戻ります。言語切替は購入を再実行せず、購入ID・承認・数量・金額・通貨を変えません。

短い案内は[クイックスタート](docs/QUICK_START.ja.md)を参照してください。以下のコマンドはリポジトリ直下で実行します。

## 前提条件とDocker起動

Gitと、Compose対応のDockerを用意してください。DockerfileはLinux ARM64・AMD64コンテナに対応し、各architectureの固定成果物を選びます。Apple SiliconのARM64はネイティブ、AMD64はエミュレーションです。buildには公式imageと固定Gemを取得するためのネットワークが必要です。ホストへのRuby・Rails・DB・Redisの導入は**不要**です。

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

x86_64ホストでは`DEMO_ARCH=amd64`を選びます。**http://127.0.0.1:3000/** を開いてください。Webプロセスは1時間で停止します。途中で止める場合は、別のターミナルで`docker stop ap2-mandate-verifier-demo`を実行します。コンテナは自動削除され、buildしたimageは残ります。インターネット公開や共有Docker cacheのpruneは行わないでください。

通常デモのホストポートは3000、購入デモは3100なので同時に起動できます。[Docker対応環境・再構築記録（英語／日本語）](docs/DOCKER_PORTABILITY_160.md)では、ネイティブとエミュレーション、過去の実測と現在のcommitのCIを区別しています。

## 通常のブラウザデモを試す

1. `/`でシナリオを選び、検証します。状態・機械判読用コード・診断・Evidenceの有無を比較します。
2. ナビゲーションから`/merchant`を開きます。販売者署名と真正なSuccess／Error Receiptを比較します。
3. `/multi-item`を開きます。Coffee × 2＋Tea × 3の正常系と、Teaが2個しかない数量不足を比較します。
4. 日本語と英語を切り替えます。選択したシナリオと結果が変わらないことを確認します。結果はプロセス内メモリに30分保持する表示snapshotです。期限切れや欠損でも、言語リンクは再生成しません。セッション消失後に販売者／複数明細ページを直接開く場合や、再実行URLでは新しい合成結果を作成します。[snapshotの動作](docs/LOCALIZATION.ja.md#通常デモの結果snapshot)を参照してください。通常fixtureのUSD、購入デモのJPYを含め、金額には通貨を明示します。

| ケース | 期待する結果 |
| --- | --- |
| 正常 | `verified_research` / `scoped_research_verified`、Evidenceあり |
| 購入内容を改ざん | `rejected` / `host_binding_mismatch`、Evidenceなし |
| 期限切れ | `rejected` / `invalid_purchase_time`、Evidenceなし |
| 通貨不足 | `rejected` / `invalid_host_context`、`order.currency`診断、Evidenceなし |
| 販売者署名＋Success Receipt | 真正性`true`、購入成功通知`true` |
| 販売者署名＋Error Receipt | 真正性`true`、購入成功通知`false`、拒否通知`true` |
| Coffee × 2＋Tea × 3 | 複数明細profileで検証成功、Evidenceあり |
| 2件目をTea × 2へ減らす | 真正な署名と金額一致でも`constraint_mismatch`、Evidenceなし |

**EvidenceもReceiptの真正性も、購入・決済の実行許可ではありません。** Receiptはアプリが通知した結果を認証します。真正なErrorは失敗であり、署名だけで精算完了を示すものではありません。通常画面では決済・実注文の更新・本番nonceの消費を行いません。

## A2A × AP2購入デモを起動する

別のCompose構成で公開Gem`ap2_mandate_verifier 1.6.0`と`a2a-rails 0.3.0`を使います。どちらのGemも変更しません。authority・buyer・sellerは別プロセスで動き、Agent間はローカルの実HTTPSで通信します。

```sh
export COMPOSE_PROJECT_NAME=ap2-purchase-demo
docker compose -f compose.purchase.yml up --build
```

1. **http://127.0.0.1:3100/** を開き、正常系を選びます。
2. お茶3袋・合計上限 **3,000 JPY**・Tea Shop・模擬支払条件を確認します。明示承認のチェックを入れ、承認を保存します。承認だけでは購入を実行しません。
3. その購入IDでAgentを実行します。正常な提示は **3 × 800 JPY = 2,400 JPY** です。
4. 四段階すべてと実行回数を確認します。AP2検証だけではなく、購入側で対応するSuccess Receiptを確認して初めて成功と判断します。
5. **同じ購入ID**で再実行し、模擬processorの回数が **1** のままであることを確認します。`timeout`も試し、新しい購入を作らず状態更新と保存済み結果での復旧を行います。

[購入デモの詳しい手順](docs/PURCHASE_DEMO.ja.md)に、八つのシナリオ、エラーと結果不明、再起動・復旧、購入履歴、信頼境界、テストをまとめています。購入画面には現在のブラウザセッションが所有する承認だけを表示します。同じホスト名とブラウザセッションを使ってください。

```sh
# Run in a terminal with the same COMPOSE_PROJECT_NAME.
docker compose -f compose.purchase.yml restart buyer seller
docker compose -f compose.purchase.yml down
```

以降も同じ`COMPOSE_PROJECT_NAME`を設定します。通常の`down`はnamed volumeと購入データを保持します。保留中の購入の復旧のためにvolumeを削除しないでください。全リセットの影響は購入ガイドで説明しています。

## オフラインのRuby例を実行する

通常imageをbuildしたら、Checkout、続いてPaymentを実行します。

```sh
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-mandate-verifier-demo:local timeout 120 bundle exec ruby examples/checkout.rb
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-mandate-verifier-demo:local timeout 120 bundle exec ruby examples/payment.rb
```

CheckoutはOpenを発行し、AgentがClosedを作って提示し、独立したHost入力に照らして検証します。期待する表示は`verified=true; rows=3; requirements=2`です。PaymentはCheckoutに結び付くDirect／条件付きMandateを試し、`Direct and conditional Payment: verified`と表示します。どちらも秘密鍵や署名原文の全文を出さず、真正なSuccess／Error Receiptを示します。

同じコマンドで、以下のファイルも実行できます。

| ファイル | 対応範囲と制限 |
| --- | --- |
| `examples/selective_payment.rb` | 保持する5disclosuresと送信する3disclosures、選択Paymentと両Receipt結果を比較します。非選択値・salt・full wireは出力しません。候補数・順序・issuer JWTのリンク可能性は隠しません。 |
| `examples/selective_checkout.rb` | 販売者・商品候補を絞ったCheckoutからPaymentへ進みます。全要件・数量は残ります。販売者と商品は独立した許可集合で、相関条件を保証しません。 |
| `examples/payment_policy.rb` | 明示的なPISP／実行日時profileでDirect・条件付き・選択的Paymentを試します。署名値を独立した信頼済み実行予定と照合し、UTCの包含境界を確認します。QWAC認証・予約・精算は行いません。 |

### 永続受理と12か月のOpen

任意の追加imageは、通常のGemfileとlockfileを変えずに固定SQLite 2.10.2を追加します。通常imageと同じ`DEMO_ARCH`を使います。

```sh
docker build --platform "linux/$DEMO_ARCH" -f Dockerfile.acceptance -t ap2-acceptance:local .
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-acceptance:local timeout 120 ruby examples/payment_acceptance.rb
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-acceptance:local timeout 120 ruby examples/long_payment_limits.rb
```

受理の例は予約・replay・原子的開始・一度の模擬dispatch・結果不明・同じDBの再open・元Receiptの復旧を比較します。本番には、全workerで共有する保護された永続DB、独立した承認occurrence、processorの冪等性と照合が必要です。timeout・新しいUUID・DBの再作成は新しい実行許可になりません。

長期Openの例は合成時計でUTCの12か月を進め、**毎月8,000 JPY・合計96,000 JPY**を**100,000 JPY**の予算内で扱います。schedulerや1年の待機なしに、12回の模擬開始と元Receipt復旧を確認します。別承認では1月と2月に各40,000 JPYを予約します。3月は署名が有効でも合計120,000 JPYとなるため拒否され、Ticketは出ず、予約は80,000 JPYのままです。この拒否比較ではprocessorを開始しません。一時DBは終了時に削除します。このimageでは`examples/long_payment.rb`も使えます。

この限定的なUTC月次JPY profileは、**AP2汎用MONTHLY仕様への完全準拠ではありません**。contentの最大期間は400日で、提示証明は短命のままです。長期の選択的開示／PISP／日時の合成、日次分割、catch-up、自動枠返却は対象外です。[SDK長期Payment契約](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/LONG_PAYMENT.md)を参照してください。

## テストと翻訳の保守

```sh
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-mandate-verifier-demo:local timeout 900 sh test/docker_validation.sh normal
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-acceptance:local timeout 600 sh test/docker_validation.sh acceptance
# With the purchase stack running; creates synthetic purchases and restarts agents.
sh test/purchase_docker_validation.sh
```

最後のスクリプトは購入構成を起動した状態で実行し、合成購入を作ってAgentを再起動します。言語の動作・翻訳更新・既存の日本語保存値・検証項目は[多言語対応](docs/LOCALIZATION.ja.md)を参照してください。[購入デモ検証記録（英語・過去の実測）](docs/PURCHASE_VALIDATION.md)、[公開1.6.0記録（日本語・過去の実測）](docs/PUBLISHED_160.md)、[Docker記録（英語／日本語）](docs/DOCKER_PORTABILITY_160.md)は、検証した環境とrevisionを示します。後続commitの成功を意味しません。現在のcommitのCIとレビューは対応するPRで確認してください。

## 対応範囲と責任境界

- 通常画面の複数明細profileは`ap2.checkout.single_merchant_multi_item` v1です。最大8明細・8要件・各要件8候補で、商品IDごとに数量を完全割当てします。同じ商品の複数行を保持し、候補の重なりを支持し、余剰・不足・二重充当を拒否します。要件IDと明細IDは別です。基本4ケースの`ap2.checkout.single_merchant_sku` v1は変更していません。
- 複数明細の税・送料・割引・複数販売者・実決済は対象外です。[複数明細契約](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/MULTI_ITEM_CHECKOUT.md)と[Python SDKとの相互運用上の差異](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/MULTI_ITEM_INTEROP.md)を参照してください。
- Direct APIには`CheckoutJWT.verify`、`Buyer.issue_closed/present_closed/verify`、1販売者・1〜8明細向けDirect Receipt profileがあります。[完全なDirect例](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/examples/direct_checkout.rb)と[API契約](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/BUYER_DIRECT_CHECKOUT.md)を参照してください。通常画面は合成のOpen → Agent Closedシナリオであり、Directの本人認証・承認UIではありません。
- 本人認証・同意・保護された承認・Provider鍵・独立した最新信頼情報・失効・注文／challenge／時刻・永続単発利用状態・最終実行許可・processor照合はアプリの責任です。購入デモは一部をローカルで示しますが、SDKの自動保証にはしません。
- 署名付きMandateとReceipt、プロトコルのキー・値、ID、機械判読用コードは翻訳しません。人が読むUIの説明を翻訳します。research profileの検証は、一般的なAP2準拠、本番Issuerの信頼、実決済の証明ではありません。

## 固定環境と出所

デモはMRI **4.0.9**、Bundler **4.0.20**、railties/actionpack **8.0.4**、Puma **6.6.1**、Minitest **5.27.0**を固定しています。Verifierは **1.6.0**、依存はJSON **2.19.9**、JWT **3.3.0**、base64 **0.3.0**、OpenSSL gem **4.0.2**、Digest **3.2.1**です。architecture別の公式Ruby digestとfrozen lockfileを維持しています。SDK単体のMRI 3.4.12／4.0.9対応と、このRailsデモのMRI 4.0.9固定は別です。他のネイティブOS／Rubyの組み合わせはここでは保証しません。

通常Dockerfileは公開Gemの **186,368 bytes** とSHA256 `62de85123e1379c538c9c4302b71a9c55c590162591169a4e335aaa03a8991f8`を導入前に検査し、同じbytesをBundlerに渡します。全 **68** ファイルのinstalled／archive一致、依存、Ruby要件、source外からのロードも確認します。Gemは再buildしません。リリースsource [`964e572`](https://github.com/cuichangquan/ap2-mandate-verifier/tree/964e572dc16d886561293cf90ddb9e2c927346bf)は、レビュー済み候補`98f7325a9dd0ee06739fe95e1306abe9b1c6ee5d`と同じtree `c9a9faaec045a9854fded3c1b4db375332a5fa57`です。取得・provider・依存の失敗時は、checksumやlockを緩めずに停止します。

`ScenarioVerifier`は署名入力のprepare・保存・restore・verifyを、独立した最新の業務状態に照らして行います。保存したbinding／digestを現在値に修復せず、提出データから信頼鍵や正規注文を推測しません。通常fixtureの固定時計は`1800000000`、期限切れは`1800000101`です。

[対応契約](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/SUPPORT_CONTRACT.md)、[販売者APIと仕様の差異](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/MERCHANT_SIGNING.md)、[MITライセンス](LICENSE)、[第三者通知](THIRD_PARTY_NOTICES.md)、[fixture通知（英語）](fixtures/input_builder/NOTICE.md)を参照してください。実行ログ・依存archive・一時セッション鍵はコミットしません。

### 過去の候補build

通常利用は上記の公開Gem用Dockerfileで完結します。`Dockerfile.candidate`、`Gemfile.candidate`、専用lockfileは、過去の **0.6.0** source比較手順として残しています。現行1.6.0のbuild手順でも、公開Gem bytesの証明でもありません。そのlockfileを通常起動に混ぜないでください。以前の記録は[履歴（英語／日本語）](docs/HISTORY.md)、[0.6.0複数明細候補（日本語）](docs/MULTI_ITEM_CANDIDATE.md)、[さらに古い候補（英語・一部日本語のラベル）](CANDIDATE.md)に残しています。
