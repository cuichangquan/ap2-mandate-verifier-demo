[English](QUICK_START.md) | [日本語](QUICK_START.ja.md)

# AP2 Ruby SDKをローカルで試す

このガイドではブラウザから始め、RubyのCheckout・Payment、別々のAgent間での購入へ進みます。鍵・注文・承認・時計・実行結果はすべて合成です。**実際の決済は行いません。** 機能一覧と対応範囲は[README](../README.ja.md)を参照してください。

## 1. 通常デモをbuildする

前提はGit、Compose対応のDocker、Linux ARM64またはAMD64コンテナです。ホストへのRuby・Rails・DB・Redisの導入は不要です。公式imageと固定Gemを取得するため、初回buildには操作手順そのものより時間がかかる場合があります。このRailsデモはMRI 4.0.9固定で、SDK単体のMRI 3.4.12対応とは別です。

```sh
git clone https://github.com/cuichangquan/ap2-mandate-verifier-demo.git
cd ap2-mandate-verifier-demo
# Use amd64 instead on an x86_64 host.
export DEMO_ARCH=arm64
docker build --platform "linux/$DEMO_ARCH" -t ap2-mandate-verifier-demo:local .
```

x86_64ホストでは`DEMO_ARCH=amd64`を選びます。Apple SiliconのARM64はネイティブ、AMD64はエミュレーションです。Dockerfileはarchitectureごとに固定Ruby・SQLite成果物を選びます。[対応環境とno-cache再構築記録（英語／日本語）](DOCKER_PORTABILITY_160.md)を参照してください。

## 2. ブラウザで検証とReceiptを比較する

```sh
docker run --rm --name ap2-mandate-verifier-demo \
  --cpus 1 --memory 512m --pids-limit 128 -p 127.0.0.1:3000:3000 \
  ap2-mandate-verifier-demo:local \
  timeout 3600 bundle exec puma -b tcp://0.0.0.0:3000 -t 1:1 config.ru
```

**http://127.0.0.1:3000/** を開きます。既定は英語で、画面上部の **English / 日本語** で切り替えます。言語はフォーム・画面遷移・再読み込みでも維持されます。未対応の言語指定は英語に戻ります。

1. 正常系を選び、Gemによる検証を実行します。`verified_research` / `scoped_research_verified`とEvidenceが表示されます。
2. 購入内容の改ざん・期限切れ・通貨不足を試します。いずれも拒否され、Evidenceはありません。通貨不足では`order.currency`が診断されます。機械判読用コードは言語で変わりません。
3. 販売者署名とSuccess／Error Receiptのリンクから`/merchant`へ進みます。両Receiptとも真正ですが、購入成功通知はSuccessだけです。真正なErrorは拒否です。
4. 複数商品・数量のリンクから`/multi-item`へ進みます。Coffee × 2＋Tea × 3は成功し、Teaを2個に減らすと、真正な署名と金額一致でも`constraint_mismatch`で拒否されます。
5. 結果画面で言語を切り替え、その表示URLを再読み込みします。言語リンクは`view=1`を含み、snapshotが欠損していても検証を再実行しません。通常の再読み込みも、同じセッションとプロセス内cacheが有効な間は結果を再利用します。snapshotは30分で失効し、サーバー再起動で消えます。セッション消失後に`/merchant`や`/multi-item`を直接開くと初回訪問として合成デモを再実行し、明示的な`?run=1` URLの再読み込みでも再実行します。保存済み結果の確認には言語／表示リンクを使ってください。保存済み結果は新たな実行許可ではありません。

通常画面はCheckout検証とReceipt APIを示し、実決済は行いません。Paymentと長期Openの例は後述します。停止は別ターミナルで`docker stop ap2-mandate-verifier-demo`を実行します。1時間でも自動停止します。

## 3. Checkout、Payment、Receiptを実行する

```sh
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-mandate-verifier-demo:local timeout 120 bundle exec ruby examples/checkout.rb
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-mandate-verifier-demo:local timeout 120 bundle exec ruby examples/payment.rb
```

CheckoutはOpenを発行し、登録済みAgentがClosedを作って提示し、独立したHost入力に照らして検証します。期待する表示は`verified=true; rows=3; requirements=2`です。PaymentはCheckoutに結び付くDirect／条件付きMandateを加えます。期待する表示は`Direct and conditional Payment: verified`です。

どちらも真正なSuccess／Error Receiptを示します。真正性`true`は購入成功通知`true`や精算完了を意味しません。同じコマンドで`examples/selective_checkout.rb`、`examples/selective_payment.rb`、`examples/payment_policy.rb`を実行すると、選択的開示と実行条件も確認できます。署名原文の全文・秘密鍵・未開示値は出力しません。

## 4. Agent間の購入を承認・実行する

別のターミナルで、リポジトリ直下から実行します。

```sh
export COMPOSE_PROJECT_NAME=ap2-purchase-demo
docker compose -f compose.purchase.yml up --build
```

**http://127.0.0.1:3100/** を開きます。別構成なので、ポート3000の通常デモと同時に使えます。

1. 正常系を選び、Tea Shopで**お茶3袋・上限3,000 JPY**の条件を確認します。明示承認のチェックを入れて承認を保存します。
2. 表示された購入IDでAgentを実行します。正常な提示は**2,400 JPY**です。承認と実行は別操作です。
3. **AP2検証**、**アプリの実行判断**、**模擬決済の結果**、**Receipt確認**を別々に読みます。processor実行回数は **1** で、購入側が対応するSuccess Receiptを確認する必要があります。
4. 同じIDで再実行します。processor回数は1のままです。新しい承認は別IDなのでreplay試験にはなりません。
5. `timeout`を承認して実行すると結果不明になります。**同じID**を更新し、保存済み結果で復旧します。代わりの購入を作らないでください。復旧しても回数は1のままで、元のReceiptを確認します。
6. 結果画面で言語を切り替え、現在のブラウザが所有する履歴から購入を開きます。ID・条件・実行回数は変わりません。

[購入ガイド](PURCHASE_DEMO.ja.md)で、八つのシナリオ、不正Receipt、エラー、セッションの所有確認、再起動、期限、全リセットを説明しています。外部LLM、実カード、決済口座、Issuerは不要です。

```sh
# Keep the same COMPOSE_PROJECT_NAME for these commands.
docker compose -f compose.purchase.yml restart buyer seller
docker compose -f compose.purchase.yml down
```

以降も同じ`COMPOSE_PROJECT_NAME`を使います。`down`はnamed volumeを保持します。結果不明を解消するために削除しないでください。履歴には現在のブラウザセッションが所有する承認だけを表示します。ホスト名とブラウザセッションを変えずに操作してください。

## 5. 任意: 12か月と予算超過を試す

先に通常imageをbuildし、同じ`DEMO_ARCH`を使います。

```sh
docker build --platform "linux/$DEMO_ARCH" -f Dockerfile.acceptance -t ap2-acceptance:local .
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-acceptance:local timeout 120 ruby examples/long_payment_limits.rb
```

この追加imageだけに固定SQLite 2.10.2を導入し、通常lockfileは変えません。一組のOpenで2028年の合成UTC月次12回を扱い、**毎月8,000 JPY**、**100,000 JPY**枠に対して**合計96,000 JPY**を予約します。12回の模擬開始と元Receipt復旧があり、1年の待機やschedulerは不要です。一時DBは終了時に削除します。

別承認では1月と2月に各40,000 JPYを予約します。3月は署名検証に成功し、回数枠も残りますが、合計120,000 JPYが予算を超えるため`acceptance=rejected`、`ticket=false`となります。予約は80,000 JPY／2件のままです。この比較ではprocessorを開始しません。状態を持たない検証だけでは過去の累計枠を管理できません。

長期contentは最大400日で、証明は短命のままです。このローカルUTC月次JPY profileは、**AP2汎用MONTHLY仕様への完全準拠ではありません**。長期の選択的開示／PISP／日時の合成、日次分割、catch-up、自動枠返却は対象外です。[詳しいSDK契約](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/LONG_PAYMENT.md)を参照してください。

## アプリに残る責任

本人認証・同意・保護された承認・独立した最新信頼情報・失効・注文／challenge／時刻・共有永続単発利用状態・最終実行許可・processorの冪等性と照合はアプリの責任です。結果不明は保留のまま扱います。timeoutやErrorによって実行権限や枠が自動復活することはありません。合成fixtureを本番の信頼情報に使わないでください。

テストコマンドと公開Gemの出所は[README](../README.ja.md)、翻訳の保守は[多言語対応](LOCALIZATION.ja.md)を参照してください。[公開1.6.0検証記録（日本語・過去の実測）](PUBLISHED_160.md)は、今回の変更の検証と分けて保持しています。

### 購入デモの起動準備とTLS更新

リポジトリ直下で `COMPOSE_PROJECT_NAME=ap2-purchase-demo` を毎回同じ値にし、`sh bin/purchase-demo start` で起動、`status` または `diagnose` で診断します。`rotate` は全役割を停止してTLS一式を更新し、購入データを保持して実通信を確認します。中断後は `recover` を使います。更新に `down -v` は使いません。[最短コマンド・保持するデータ・失敗時の復旧](PURCHASE_DEMO.ja.md)を参照してください。
