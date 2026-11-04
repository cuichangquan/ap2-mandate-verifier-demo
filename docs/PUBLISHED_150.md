# 公開1.5.0へのデモ更新と検証

[RubyGems 1.5.0](https://rubygems.org/gems/ap2_mandate_verifier/versions/1.5.0) は2026-11-04T13:05:50.125Z登録。実配布Gemは160,256 bytes、SHA256 `9fdd419d031ff10b17c5a9bf31afc74a5f03a70cdcb442d7b4c561f6f90f1802`。正式リリースsourceは [`29db1b2`](https://github.com/cuichangquan/ap2-mandate-verifier/tree/29db1b269f08b59dd4da210c1fa374d14d9df48d)。レビュー済み候補source `456ecd634b76fb05cabd37da9c05c1662b462f07` と同一tree `d5cae07d62c51a02dbdf8bd459d175b74a9d4de3` です。

通常Dockerfileは公開Gemを取得してsize/SHAを照合し、その同じbytesをBundler cacheへ渡してfrozen installします。導入後は全58ファイルのarchive/installed一致、固定5依存、Ruby要件、demo外からのロードを確認します。lock差分はVerifier版2箇所とchecksumだけで、他の依存版・制約・checksumは不変です。Gemの再build・再pushは行いません。

固定arm64 Ruby4.0.9 baseから通常経路をfresh buildしました。network none／CPU1／memory512m／pids128／timeout120秒で以下を実測しています。

| 確認 | 結果 |
| --- | --- |
| installed_gem_check.rb | 1.5.0 /160,256 bytes /SHA一致 /全58 payload一致 |
| demo_test.rb | 7 runs /173 assertions /failures・errors・skips 0 |
| merchant_scenario_test.rb | 1 run /13 assertions /failures・errors・skips 0 |
| multi_item_scenario_test.rb | 3 runs /35 assertions /failures・errors・skips 0 |
| payment /selective_payment /selective_checkout /payment_policy | 公開Gemの全4例成功 |
| payment_acceptance | 初回reserved、再署名再送pending、模擬dispatch一回、unknown再open、遅延Receipt復旧、再Ticketなし |
| 追加image context | Dockerfile・専用ignore・公開entryの3ファイルだけ。環境ファイル・候補key・private sentinelを除外 |
| 通常imageの任意driver不在 | require時の読み込みなし。storeはUnavailable、DB作成・メモリfallbackなし |

通常imageが取得したGemと独立にダウンロードした公開Gemを全バイト比較して一致しました。例の出力に秘密鍵、JWT原文、salt、fence、processor key実値、非選択候補がないことも確認しています。

通常Railsと従来のRuby単体例は公開1.5.0を使用します。任意の `Dockerfile.acceptance` だけがsqlite3=2.10.2 ARM64ネイティブGem（SHA256 `e9aea2c2b3476fc875dd8a89313a9a2862818519c0186bfb5b56d6f57bb08d98`）をDocker内に追加します。SDK基礎依存と通常Gemfileには追加しません。通常SDKのrequireでdriverを読み込まず、driverがなければstore初期化はUnavailableです。メモリstoreへfallbackしません。

```sh
docker build --platform linux/arm64 -t ap2-mandate-verifier-demo:local .
docker build --platform linux/arm64 -f Dockerfile.acceptance -t ap2-acceptance:local .
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-acceptance:local timeout 120 ruby examples/payment_acceptance.rb
```

追加imageは公開Gem導入済みの通常imageを使い、候補Gem・SDK source overlayを読みません。専用deny-all build contextは公開例entryとDocker設定だけを許可します。旧candidate名entry、Dockerfile、候補説明は履歴として保持しています。

例は合成一時SQLiteと模擬processorです。原子的予約後も開始時に完全検証を再実行し、再送では新Ticketを出しません。結果不明はunknownに保持し、同じDBを開き直して保存済みprocessor照会key・元のClosedに結合した遅延Receiptで復旧します。秘密鍵・salt・full wire・Ticket fence・非選択候補は出力しません。

本番では一時DB、worker別DB、起動時の無条件DB再作成を使ってはいけません。保護された承認とoccurrence、全worker共通の永続DB、最新Host情報、原子的開始CAS、PSP側の冪等性・照会・復旧が必要です。timeoutやError Receiptで自動解放せず、任意UUIDを新しい承認にしません。Standing Openは別途承認したoccurrenceと新しいClosedで再利用できます。Receipt真正性は外部決済・精算完了の証明ではありません。SQLite参照adapterは単一host向けで、分散DB、backup rollback、filesystem障害、実決済のexactly-onceを保証しません。
