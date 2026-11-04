# 公開1.4.0へのデモ更新と検証

[RubyGems 1.4.0](https://rubygems.org/gems/ap2_mandate_verifier/versions/1.4.0) は2026-11-04T03:17:55.109Z登録。通常Docker buildで実配布Gemを取得し、145,920 bytes、SHA256 `ea82c6468f339ed280005e1a270a511b1a8594452ef3de6fb546de43aa6ba454` を照合します。正式リリースsourceは [`b062479`](https://github.com/cuichangquan/ap2-mandate-verifier/tree/b0624799f4d9e7cecc3f5b72b5ed760a81ca456c)。レビュー済み候補source `76239c94d7d6966419ae05871fa58b158074a000` と同一tree `5075fe56f89b5f150627d9ad5db1e4a811f9b3e1` です。

通常Gemfile/lock/Dockerfileを公開Gemへ更新します。lock差分はVerifier版2箇所とchecksumだけで、他の依存版・制約・checksumは不変です。size/SHAを照合した同じbytesをBundler cacheに渡してfrozen installし、全53ファイルのarchive/installed一致、固定5依存、Ruby要件、demo外からのロードを確認します。Gemの再build・再pushは行いません。

固定arm64 Ruby4.0.9 baseから通常経路をfresh buildしました。以下は実配布Gemから作ったimageで、network none／CPU1／memory512m／pids128／timeout120秒で実測した結果です。

| 確認 | 結果 |
| --- | --- |
| installed_gem_check.rb | 1.4.0 /145,920 bytes /SHA一致 /全53 payload一致 |
| demo_test.rb | 7 runs /173 assertions /failures・errors・skips 0 |
| merchant_scenario_test.rb | 1 run /13 assertions /failures・errors・skips 0 |
| multi_item_scenario_test.rb | 3 runs /35 assertions /failures・errors・skips 0 |
| payment.rb /selective_payment.rb /selective_checkout.rb | 全例の署名・Host結合・Receipt確認が成功 |
| payment_policy.rb | 3モードと両Receipt結果を確認。独立PISP・時刻不一致、日時窓外を拒否 |

```sh
docker build --platform linux/arm64 -t ap2-mandate-verifier-demo:local .
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-mandate-verifier-demo:local timeout 120 bundle exec ruby examples/payment_policy.rb
```

新しい通常entry `examples/payment_policy.rb` は公開Gem同梱の例を読み、選択的Checkoutに結合したDirect・条件付き・選択的Paymentを試します。PISPと実行日時は新しい明示profileだけで扱い、旧APIの既定値・保存形式・profileを変更しません。新profileのClosedでは両方必須です。PISPと日時は非開示にせず、独立したアプリの信頼済み実行予定と照合します。日時の包含境界は文字列順序ではなくUTC瞬間で比較します。

対応日時は厳格なRFC3339の限定subsetです。明示timezone、実在Gregorian日付、最大9桁小数を扱い、うるう秒・未知offset `-00:00`・timezoneなし等は拒否します。固定Open日時は原文一致、独立contextは等価なoffset表記の同一瞬間を許容します。PISPはlegal_name・brand_name・domain_nameの3項目を照合しますが、QWACや接続先の認証を行いません。

既存の `examples/payment.rb`、`examples/selective_payment.rb`、`examples/selective_checkout.rb` も通常1.4.0を使用します。旧候補Dockerfileとcandidate名entryは履歴として保持し、通常経路では使用しません。Rails画面は従来の合成シナリオのままで、新機能はRuby単体例です。

候補集合の相関は保証しません。必要ならOpenを分割してください。Receipt真正性・検証成功は実行予約・実決済・精算・最終購入許可の証明ではありません。同意、鍵trust、失効、注文現在性、nonce原子消費、重複防止、結果不明時の照合はアプリ責任です。全鍵・データは合成で、デプロイや認証設定変更はありません。
