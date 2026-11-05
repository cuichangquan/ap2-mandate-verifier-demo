# JPY・ON_DEMANDの回数／予算制約 — 1.6.0候補

未公開候補GemのRuby単体例です。通常Railsと通常Ruby例は公開1.5.0を維持し、この経路はローカルの合成SQLite/mockだけを使用します。公開はOwnerの最終判断待ちです。

対象は明示的な `RecurringPayment` profileで、JPY整数、`frequency: "ON_DEMAND"`、上限付き回数、単一累積予算に限定します。署名付きOpenの回数・予算制約は完全表示し、選択的profileで隠せるのは非選択payee／instrument候補だけです。月次などのcalendar frequency、期間ごとのreset、JPY以外、曖昧な小数単位、PISP・実行日時profileとの組み合わせは扱いません。既存の最大有効期間600秒を延長しません。

通常1.5.0 imageと任意SQLite imageを先に用意します。`Dockerfile.acceptance` は任意driver sqlite3=2.10.2をDocker内だけに追加し、SDK基礎依存には加えません。

```sh
docker build --platform linux/arm64 -t ap2-mandate-verifier-demo:local .
docker build --platform linux/arm64 -f Dockerfile.acceptance -t ap2-acceptance:local .
```

プレビュー候補を `candidate/ap2_mandate_verifier-1.6.0.gem` へ置きます。現在の候補は171,008 bytes、SHA256 `f431c6584af2fda1cded9012424d8e428664036e2cd994c8e9fdb44de8a83843` です。独立レビュー中の未公開プレビューで、公開承認済みartifactではありません。修正で候補が変わった場合はbyte数・SHAを再照合し、検証前の値や既存versionのGemを代用しません。

```sh
docker build --network none -f Dockerfile.recurring-candidate \
  --build-arg CANDIDATE_BYTES=171008 \
  --build-arg CANDIDATE_SHA256=f431c6584af2fda1cded9012424d8e428664036e2cd994c8e9fdb44de8a83843 \
  -t ap2-recurring-candidate:local .
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-recurring-candidate:local timeout 120 ruby examples/recurring_payment_candidate.rb
```

上記プレビューをnetwork noneでbuildし、インストール済みGemの例をCPU1／memory512m／pids128／timeout120秒で確認しました。独立して承認した2回・600JPYを予約し、3回目を拒否、再署名再送でTicketを増やさず、unknownで回数2・金額600JPYを保持します。専用contextの実測は候補Gemとentryの2ファイルのみで、環境ファイル・候補key・private Ruby sentinelの3つを除外しました。出力に秘密鍵・JWT原文・salt・fence・processor key実値はありません。通常公開1.5.0 imageのRails関連221 assertionsも失敗・error・skipなしで確認しています。これらはプレビューの限定観測であり、独立レビュー完了・公開承認を意味しません。

wire検証は署名・全必須制約・Checkout／Host結合を確認しますが、累積回数や予算を予約した結果ではありません。`RecurringSQLiteStore` は保護されたseriesと別途承認したoccurrenceを照合し、予約・回数・予算を同じtransactionで更新します。再送は重複加算せず、unknownやError Receiptで予算を自動返却しません。Open全体を一律一回限りにせず、独立した承認・新しいClosed・残枠の条件で再利用します。

series用schemaは既存1.5 ledgerと別契約で、暗黙の移行や再作成を行いません。本番では全worker共通の保護された永続DB、独立した承認、最新Host state、PSPの冪等性・照会・復旧が必要です。例の一時DBを本番の台帳に使ってはいけません。秘密鍵・salt・full wire・fence・非選択候補は出力しません。Receipt真正性・予算予約は実決済や精算、外部exactly-onceの証明ではありません。
