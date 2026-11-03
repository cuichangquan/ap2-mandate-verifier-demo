# 公開1.2.0へのデモ更新と検証

OwnerのRubyGems登録は2026-11-03T12:30:27.200Z。実配布Gemは129,536bytes、SHA256 `327ddb9f19e2b6348631ccb38838abd8247b4b7c2dfeb3ce2cf53bc2b0961443`で承認候補・GitHub Release添付物と全バイト一致します。[本体の公開検証](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/POST_RELEASE_120.md)、[Release v1.2.0](https://github.com/cuichangquan/ap2-mandate-verifier/releases/tag/v1.2.0)。公開source `52ebc7cb37f20967d4a53d88c57e347b0bc4b769`はreviewed `fd79d2c230eaa2cd2d65f4bb7394351b5a60c1ea`と同一treeです。

通常Gemfile/lock/Dockerfileを公式公開1.2.0へ更新。lock差分はVerifier版2箇所とchecksum1箇所だけで、他の依存版・制約・checksumは不変です。Dockerfileでsize/SHAを確認し、同じ公開bytesをBundler cacheへ渡してBUNDLE_FROZEN=trueで導入します。再build／再pushはしません。通常導入後の全44archive/installed payload一致、固定5依存・Ruby要件・source外ロードを確認します。

既存の公式arm64 Ruby4.0.9 base digestでfresh buildし、network none／CPU1／memory512m／pids128で以下を実測しました。

| 確認 | 結果 |
| --- | --- |
| demo_test.rb | 7runs /173assertions /failure0 /error0 |
| merchant_scenario_test.rb | 1run /13assertions /failure0 /error0 |
| multi_item_scenario_test.rb | 3runs /35assertions /failure0 /error0 |
| installed_gem_check.rb | 1.2.0 /129,536bytes /SHA一致 /全44payload一致 |
| examples/payment.rb | 旧完全内容profileのDirect／条件付きPayment、Success／Error Receiptが成功 |
| examples/selective_payment.rb | 保持5→送信3disclosures、issuerJWT不変・提示bytes変更、完全Checkout結合と選択Payment、Success／Error Receiptが成功 |

```sh
docker build --platform linux/arm64 -t ap2-mandate-verifier-demo:local .
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-mandate-verifier-demo:local timeout 120 bundle exec ruby examples/selective_payment.rb
```

`Payment`は既存の完全内容profile、`SelectivePayment`は候補配列要素だけを隠せる明示profileです。旧candidate名entryは公開1.2.0例の互換aliasとして保持します。Dockerfile.selective-candidateは過去のローカルarchive比較経路で、通常利用や公式配布bytesの証明には使いません。

相関subsetは署名前に拒否し、別Openへの分割が必要です。候補数・順序・issuerJWTlinkageは隠れず、Python相互運用は明示低水準profileadapterの範囲です。全鍵・データ・結果は模擬で、本人認証・同意・鍵trust・永続的重複防止・原子的状態更新・実決済・未知結果照合はアプリ責任です。Rails決済UI／livePSP／Webデプロイ／実決済／認証設定変更は追加していません。
