# 長期Open・明示UTC月期間 — 別経路の1.6.0候補

未公開のLong profile候補を使うローカルRuby例です。通常Rails、通常Gemfile・lock・Dockerfileは公開1.5.0のままです。以前のbounded ON_DEMAND候補も比較履歴として保持し、この長期候補と同じarchiveや経路で置き換えません。公開・デプロイ・実決済は行いません。

新しい `LongPayment` とLong Checkout profileだけが、共有contentの有効期間を最大400日まで扱います。既存Paymentの600秒、既存Checkoutの7,200秒制限と既定profileは変更しません。例は同じOpen Checkout／Paymentを、閏年の12期間で使用します。Closed contentの `iat/exp` は元Openと完全一致し、外側KB-JWTの時刻・audience・nonce、現時点の独立Host trust・challenge・注文状態を毎回検証します。proof ageは300秒のままです。

MONTHLYは保護されたHostの明示UTC calendar-month policyです。各windowは一つのUTC月内に収まり、同じUTC年月にwindowは一つだけです。狭い実行windowは指定できますが、日次分割・catch-up・暗黙timezone/DST・汎用AP2カレンダー規則には拡張しません。JPY整数額、有限回数、単一累積予算に限定し、long selective・PISP／execution-date profileとの組み合わせは対象外です。

まず通常1.5.0 imageと、Docker内だけにsqlite3=2.10.2を追加する任意imageを用意します。ホストへのインストールやSDK基礎依存の追加は不要です。

```sh
docker build --platform linux/arm64 -t ap2-mandate-verifier-demo:local .
docker build --platform linux/arm64 -f Dockerfile.acceptance -t ap2-acceptance:local .
```

長期候補を `candidate/long/ap2_mandate_verifier-1.6.0.gem` に置きます。現在の独立レビュー済みSDK未公開候補は186,368 bytes、SHA256 `62de85123e1379c538c9c4302b71a9c55c590162591169a4e335aaa03a8991f8`、source `98f7325a9dd0ee06739fe95e1306abe9b1c6ee5d` です。SDKレビューは完了していますが、Demoの独立レビューとOwnerの公開判断は別途必要です。元のbounded候補ファイルを上書きしません。この経路はsize／SHAが未指定または不一致なら導入前に停止し、レビュー修正で候補が変わった場合は再照合します。

```sh
docker build --network none -f Dockerfile.long-candidate \
  --build-arg CANDIDATE_BYTES=186368 \
  --build-arg CANDIDATE_SHA256=62de85123e1379c538c9c4302b71a9c55c590162591169a4e335aaa03a8991f8 \
  -t ap2-long-candidate:local .
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-long-candidate:local timeout 120 ruby examples/long_payment_candidate.rb
```

同梱の `examples/long_payment_acceptance.rb` を実行し、同じOpen pairから12回×8,000JPY＝96,000JPYを100,000JPY予算内で予約します。開始ごとに新しいproofと現在の権限を再検証し、元のClosedに結合したReceiptを照合します。dispatchは合成のプロセス内mockです。秘密鍵・salt・raw JWT・fence・非選択候補は出力しません。

上記62de8512候補をnetwork noneでbuildし、CPU1／memory512m／pids128／timeout120秒でinstalled acceptance例と全12か月のwire例を確認しました。専用contextは長期候補Gemとentryの2ファイルのみで、環境ファイル・候補key・private Ruby sentinelの3つを除外しました。出力のprivacy検査も合格しています。通常Gemfile／lock／Dockerfileは不変で、同じimage内でもBundlerが公開1.5.0を選び全58 payload一致を確認しました。通常Railsの直近221 assertionsは設定不変のため再実行していません。これは上記候補に限定した観測で、Demoの独立レビュー合格や公開承認の証明ではありません。

Issuer／Agent／Merchantの現在の信頼contextは受信tokenから選ばず、独立したHost入力を使います。外部registryの変更と保護された台帳epochの同期はアプリ責任で、自動的な外部失効検知ではありません。権限更新とRoot置換はCASで行い、Issuer／Agent鍵の変更には新しい完全Root pairが必要です。Root更新はCheckoutの全条件・候補とPayment固定条件を比較し、権限主体のidentity／purpose／tenantも保護します。回数・累積予算・period使用済み状態はRootを替えてもresetしません。

Long用schemaは既存ledgerと別契約で、schema1／2からの自動移行、台帳の再作成、timeoutやError Receiptによる自動解放は行いません。例は一時SQLiteを使います。本番では全worker共通の保護された永続DB、独立した承認、外部processorの冪等性・照会・障害復旧が必要です。

固定公式Python SDKとの比較ではbudgetの倍率100の評価経路などに差があります。このprofileはHostのJPY整数予算と明示UTC期間を基準にし、独立した期待値で検証します。公式SDKの汎用MONTHLY適合、実決済・精算、外部exactly-onceの証明ではありません。この文書は未公開候補用です。Demoの独立レビューとOwnerの公開判断は別途必要です。
