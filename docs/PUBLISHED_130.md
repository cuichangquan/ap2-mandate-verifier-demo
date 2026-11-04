# 公開1.3.0へのデモ更新と検証

[RubyGems 1.3.0](https://rubygems.org/gems/ap2_mandate_verifier/versions/1.3.0) は2026-11-04T00:29:50.504Z登録。通常Docker buildが取得した実配布Gemは137,728 bytes、SHA256 `fb95cf669bc4cba1cc1360653bfd7ae8aec58404f13810f6d5a8fb205bc8841d`。承認候補と一致します。sourceは [`fd9e7a3`](https://github.com/cuichangquan/ap2-mandate-verifier/tree/fd9e7a3f0a2319089be7197a4d585083861884f1)。

Gemfileと通常lockを公開1.3.0へ更新しました。lock差分はVerifier版2箇所とchecksumだけで、他の依存版・制約・checksumは不変です。Dockerfileは取得Gemのsize/SHAを照合し、その同じbytesをBundler cacheへ渡してfrozen installします。導入後は全49ファイルのarchive/installed一致、固定5依存、Ruby要件、demo外からのロードを検査します。Gemの再build・再pushは行いません。

公式arm64 Ruby4.0.9の固定baseから通常経路をfresh buildし、network none／CPU1／memory512m／pids128／timeout120秒のコンテナで実測しました。

| 確認 | 結果 |
| --- | --- |
| demo_test.rb | 7 runs /173 assertions /failures・errors・skips 0 |
| merchant_scenario_test.rb | 1 run /13 assertions /failures・errors・skips 0 |
| multi_item_scenario_test.rb | 3 runs /35 assertions /failures・errors・skips 0 |
| installed_gem_check.rb | 1.3.0 /137,728 bytes /SHA一致 /全49 payload一致 |
| examples/payment.rb | Direct・条件付きPaymentと両Receipt結果を検証 |
| examples/selective_payment.rb | 保持5→送信3、Issuer JWT不変、選択Paymentと両Receipt結果を検証 |
| examples/selective_checkout.rb | Checkout保持6→送信4、Issuer JWT不変、全要件・数量とHost結合、続く選択Payment・両Receipt結果を検証 |

通常のRuby単体entryは `examples/payment.rb`、`examples/selective_payment.rb`、新しい `examples/selective_checkout.rb` です。最後のentryは公開Gem同梱のCheckout＋Payment連続例を実行します。機密の完全Openは保持用、販売者へ渡すwireは候補を絞った提示用です。非選択値・full wire・salt・秘密鍵は出力しません。

```sh
docker build --platform linux/arm64 -t ap2-mandate-verifier-demo:local .
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-mandate-verifier-demo:local timeout 120 bundle exec ruby examples/selective_checkout.rb
```

旧 `Dockerfile.checkout-candidate` と `examples/selective_checkout_candidate.rb` は候補比較の履歴として保持します。通常経路には候補archiveやSDK source overlayを使用しません。Rails画面は従来の合成シナリオを維持し、新しい選択的CheckoutはRuby単体例で確認できます。

販売者・各要件の商品候補は独立した集合で、相関が必要なら別Openへ分割します。候補数・位置・issuerJWTのリンク可能性は隠しません。検証成功は最終購入許可ではなく、Receipt真正性も実決済の確定ではありません。同意、鍵trust、失効、注文現在性、nonce原子消費、重複防止、実決済はアプリ責任です。全データ・鍵は合成、Webデプロイや認証設定変更はありません。
