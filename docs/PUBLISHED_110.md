# 公開1.1.0への更新・検証

RubyGems登録は2026-11-03 09:20:11.580 UTC。公開Gemは115,200 bytes、SHA256 `4c64cf5b6c61ae4395577828093a6f4022c35cf18b6ad1bcfcb9f95fbb4f43c9`で承認候補と全バイト一致します。[本体の公開照合記録](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/POST_RELEASE_110.md)、[Release v1.1.0](https://github.com/cuichangquan/ap2-mandate-verifier/releases/tag/v1.1.0)。

公開source `89e779cadeac0ea7941e68f12951eed13f1b8081`はreviewed/tested `631537ec52c33c3472fd856da55faeff3fb62203`と同一tree。1.0.0 Checkout公開契約・5固定依存を維持し、Direct／条件付きPaymentとPayment Receiptを追加します。Gemは再build・再pushせず、通常Dockerfileから公式公開archiveを取得し、size/hash確認後に同じbytesをBundler cacheへ渡します。

Gemfile/lockのVerifier pinを1.1.0へ更新。他の依存版・制約・checksumは不変です。lock差分はVerifier版2箇所とchecksum1箇所だけで、BUNDLE_FROZEN=trueによる構築が成功しました。全38archive/installed payloadが一致し、Gemはデモsource外から通常ロードされます。

既存の公式arm64 Ruby4.0.9 base digestでfresh buildし、network none／CPU1／memory512m／pids128のDockerで以下を実測しました。

| 確認 | 結果 |
| --- | --- |
| demo_test.rb | 7 runs / 173 assertions / failure 0 / error 0 |
| merchant_scenario_test.rb | 1 run / 13 assertions / failure 0 / error 0 |
| multi_item_scenario_test.rb | 3 runs / 35 assertions / failure 0 / error 0 |
| installed_gem_check.rb | 1.1.0 / 115,200 bytes / SHA一致 / 全38payload一致 |
| examples/payment.rb | Direct／条件付きPayment検証、両経路のSuccess／Error Receipt、結果不明時pendingが成功 |

```sh
docker build --platform linux/arm64 -t ap2-mandate-verifier-demo:local .
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-mandate-verifier-demo:local timeout 120 bundle exec ruby examples/payment.rb
```

PaymentはGemに同梱されたRuby単体例を使います。Rails画面へ認証・決済UIや実PSP接続は追加していません。旧examples/payment_candidate.rbも公開1.1.0を指定する互換entryとして残します。Webデプロイ・実決済・実顧客データ・本番秘密鍵・認証設定変更は行っていません。検証成功は実行許可ではなく、永続的な単発利用と原子的状態遷移・Receipt不明時の照合は利用アプリの責任です。
