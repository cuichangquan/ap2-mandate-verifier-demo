# 公開1.6.0へのデモ更新と検証

[RubyGems 1.6.0](https://rubygems.org/gems/ap2_mandate_verifier/versions/1.6.0) の実配布Gemは186,368 bytes、SHA256 `62de85123e1379c538c9c4302b71a9c55c590162591169a4e335aaa03a8991f8`。[正式リリース](https://github.com/cuichangquan/ap2-mandate-verifier/releases/tag/v1.6.0) sourceは `964e572dc16d886561293cf90ddb9e2c927346bf`、レビュー済み候補sourceは `98f7325a9dd0ee06739fe95e1306abe9b1c6ee5d` です。

通常Dockerfileは公開Gemを取得しsize/SHAを照合して、その同じbytesをBundler cacheからfrozen installします。全68 payloadのarchive/installed一致、固定5依存、Ruby要件、demo外からのロードを確認します。lock差分はVerifier版2箇所とchecksumだけで、他の依存は不変です。SDK source overlayや候補Gem、Gemの再build・再pushは使いません。

## 公開Gemの長期Open例

```sh
docker build --platform linux/arm64 -t ap2-mandate-verifier-demo:local .
docker build --platform linux/arm64 -f Dockerfile.acceptance -t ap2-acceptance:local .
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-acceptance:local timeout 120 ruby examples/long_payment.rb
```

任意の追加imageだけが固定sqlite3=2.10.2 ARM64 Gem（SHA256 `e9aea2c2b3476fc875dd8a89313a9a2862818519c0186bfb5b56d6f57bb08d98`）をDocker内へ導入します。通常GemfileとSDK基礎依存には追加しません。driverがない場合はUnavailableで、メモリstoreへfallbackしません。追加contextはDocker設定2ファイルと公開entry2ファイルだけを許可します。

同じ完全開示Open CheckoutとOpen Paymentを12の明示UTC月期間で使い、各月8,000円、合計96,000円を100,000円の予算内で予約します。各開始時のfresh proof・最新Host authorityとCAS、元のClosedに結合したReceipt復旧を確認する合成SQLite/mock例です。実決済、精算、外部processorのexactly-onceを証明しません。

Long profileだけのcontent上限は400日です。従来Payment600秒／Checkout7,200秒は変えません。Closedのcontent iat/expはOpenと同じまま、outer KB proofは独立して0〜300秒のfreshnessを要求します。MONTHLYは保護された明示UTC calendar windowを各月1つだけ登録するローカルprofileです。短い実行windowは許可しますが、日次分割、catch-up、暗黙timezone/DST、汎用AP2のcalendar semanticsは扱いません。JPY整数・有限回数／予算のみで、Longの選択的開示やPISP/date合成は対象外です。

外部registryの変更を永続ledgerのauthority epochへ同期する責任はHostにあります。Root鍵rotationは署名済みOpen pair、同じtenant・principal identity／purpose・経済条件の確認とCASが必要です。Merchant/current authority変更も保護された更新を経由します。期間ID別名や再署名を新しい消費枠にせず、Root更新で回数／予算をresetしません。既存schemaからの自動migration、DB再作成、timeout・Error Receiptによる自動解放はありません。

固定公式Python SDKのbudget倍率100の評価経路とは差があるため、JPY整数予算と独立Host期間policyを基準にします。公式SDKの汎用MONTHLY適合を主張しません。実運用には全worker共通永続DB、保護された承認・最新注文／trust、PSP照会と復旧、backup rollbackへの対処が別途必要です。

旧[bounded候補](RECURRING_PAYMENT_CANDIDATE.md)・[長期候補](LONG_PAYMENT_CANDIDATE.md)・[公開1.5.0記録](PUBLISHED_150.md)は履歴として維持します。

## 今回の実測

固定arm64 Ruby4.0.9通常imageを公開Gemからfresh buildしました。実行はnetwork none／CPU1／memory512m／pids128／timeout120秒を上限とし、短い試験には60秒以下を使いました。

| 確認 | 結果 |
| --- | --- |
| installed_gem_check.rb | 1.6.0／186,368 bytes／SHA一致／全68 payload一致 |
| demo_test.rb | 7 runs／173 assertions／failures・errors・skips 0 |
| merchant_scenario_test.rb | 1 run／13 assertions／failures・errors・skips 0 |
| multi_item_scenario_test.rb | 3 runs／35 assertions／failures・errors・skips 0 |
| payment／selective_payment／selective_checkout／payment_policy | 公開Gemの4例成功 |
| payment_acceptance | 再署名再送pending／mock開始1回／unknown再open／遅延Receipt復旧 |
| long_payment | 同じOpen pairで12期間／mock開始12回／96,000円予約／元のReceipt復旧 |
| installed long wire例 | 全12か月のfresh検証と共有content時刻の保持に成功 |
| driver不在 | requireでは未ロード／storeはUnavailable／DB fallbackなし |
| 追加image context | 許可4ファイルのみ。環境・候補key・private Rubyの3 sentinelを除外 |

出力に秘密鍵・JWT原文・salt・fence・processor key実値がないことを検査しました。回数は同一process内の模擬counterで、外部processor・並行process・障害時のexactly-once試験ではありません。候補archiveと履歴文書は変更していません。
