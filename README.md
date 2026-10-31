# AP2 購入委任・販売者署名のローカルデモ

公開済み [ap2_mandate_verifier 0.6.0](https://rubygems.org/gems/ap2_mandate_verifier/versions/0.6.0) を通常起動で使うRailsデモです。InputBuilderの検証・診断・Evidence、販売者のCheckout JWT署名、複数商品・数量、真正なSuccess／Error Receiptを試せます。

## Dockerで起動

GitとDockerを用意してください。DB・Redis・ホストへのRuby導入、環境変数や候補Gemfileの指定は不要です。

```sh
git clone https://github.com/cuichangquan/ap2-mandate-verifier-demo.git
cd ap2-mandate-verifier-demo
docker build --platform linux/arm64 -t ap2-mandate-verifier-demo:local .
docker run --rm --name ap2-mandate-verifier-demo \
  --cpus 1 --memory 512m --pids-limit 128 -p 127.0.0.1:3100:3000 \
  ap2-mandate-verifier-demo:local \
  timeout 3600 bundle exec puma -b tcp://0.0.0.0:3000 -t 1:1 config.ru
```

http://127.0.0.1:3100/ で従来の4検証ケースを選びます。「販売者署名と成功・拒否Receipt」と「複数商品・数量」のリンクから、各APIの結果を比較できます。画面の0.6.0・status/code・診断・Evidence・Receiptの真正性と業務結果を確認してください。終了は `docker stop ap2-mandate-verifier-demo`。Web公開や共有cacheのpruneは行いません。

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

## 複数商品・数量

http://127.0.0.1:3100/multi-item はCoffee2個＋Tea3個の成功と、Tea2個だけの不足を比較します。真正なSuccess／Error Receiptも表示し、Errorでも署名検証はtrue、購入成功通知はfalseになります。

ページは入力構築・prepare・保存・restore・現在状態のverify・Checkout署名・Receipt署名と検証を公開APIで実行します。Issuer／Agent envelopeはデモ内の合成試験処理で、製品発行APIではありません。

明示profileは `ap2.checkout.single_merchant_multi_item` v1です。最大8明細・8要件・各8候補、商品IDで数量を完全割当てし、要件IDと明細IDは別です。同じ商品の複数行を保持し、候補の重なりを支持し、余剰・不足・二重充当を拒否します。旧 `ap2.checkout.single_merchant_sku` v1は通常4ケースで引き続き利用し、定義と受理範囲は変えていません。

税／送料／割引・複数販売者・実決済は対象外です。[複数明細契約](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/MULTI_ITEM_CHECKOUT.md)、[公式Python SDKとの差異](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/MULTI_ITEM_INTEROP.md)、[今回の公開Gem検証](docs/PUBLISHED_060.md)を参照してください。

**EvidenceもReceipt真正性も購入・決済の実行許可ではありません。** 業務結果はアプリが明示し、実決済・注文更新・nonce消費は行いません。すべて合成データ・メモリ内テスト鍵で、実Issuerの信頼を示しません。固定時計は1800000000、期限切れケースは1800000101です。

## テスト

```sh
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-mandate-verifier-demo:local sh -c \
  'timeout 120 bundle exec ruby test/demo_test.rb && timeout 60 bundle exec ruby test/merchant_scenario_test.rb && timeout 60 bundle exec ruby test/multi_item_scenario_test.rb'
```

公開0.6.0のfresh build・今回の実測結果は[公開Gem検証記録](docs/PUBLISHED_060.md)へ記録します。過去の候補試験を今回のPASSとして数えません。

## 固定構成・責任境界

MRI4.0.9、Bundler4.0.20、railties/actionpack8.0.4、Puma6.6.1、Minitest5.27.0。Docker baseは既存の公式arm64 digestに固定しています。Verifier0.6.0とJSON2.19.9／JWT3.3.0／base640.3.0／OpenSSL gem4.0.2／Digest3.2.1を使用します。

Dockerfileは公式Gemの **56,832 bytes** とSHA256 `ff669a62717f91b2295b3cea1b68c6c4143c490d98df071fd322ad4b0007195d` を導入前に照合し、同じbytesをBundler cacheへ渡します。Gemは再buildしません。公開sourceは [`baee59a`](https://github.com/cuichangquan/ap2-mandate-verifier/tree/baee59a603d08123adc0af50e57c8710ea62f4f9)。取得／provider／依存の失敗時は停止し、lockやchecksumを緩めません。

`ScenarioVerifier` は独立した業務情報と署名原文からprepare→保存→restore→現在状態→verifyを行います。保存したB／digestを現在値へ修復せず、利用者入力から鍵・期待注文を推測しません。

[対応契約](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/SUPPORT_CONTRACT.md)／[Merchant API・仕様とSDK差異](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/MERCHANT_SIGNING.md)／[過去の候補・実測履歴](docs/HISTORY.md)。実Issuer・Host本番・原子的nonce消費・失効・性能・Web運用等のHOLDは維持します。他OS／architectureやデモのRuby3.4.12は未検証です。[MIT](LICENSE)、[出所通知](THIRD_PARTY_NOTICES.md)、[業務fixture通知](fixtures/input_builder/NOTICE.md)を保持します。実行ログ・依存archive・一時セッション鍵はコミットしません。

## 開発source比較用の候補手順

通常利用は上記Dockerfileだけで完結します。`Dockerfile.candidate`／`Gemfile.candidate` はローカルsourceの比較用として別経路に残しています。公開Gemと同じversion表示でもそのbuild物は公開bytesの証明にならず、公開Gemの代用にしません。この公開後整備では候補Gemをbuildしません。

過去の候補起動・試験は[0.6.0候補の歴史記録](docs/MULTI_ITEM_CANDIDATE.md)へ、さらに古い候補は[CANDIDATE.md](CANDIDATE.md)へ残しています。

![歴史記録：公式0.5.0による成功・拒否Receiptの実画面](docs/images/merchant050.jpg)
