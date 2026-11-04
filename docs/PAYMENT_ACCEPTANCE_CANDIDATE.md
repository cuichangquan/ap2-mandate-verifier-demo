# Payment受理・冪等性支援 — 1.5.0候補

未公開候補を使うRuby単体デモです。通常Railsは公開1.4.0を維持します。SDKは実決済を呼ばず、SQLiteと模擬counterで受理・再送・結果不明・Receipt復旧を示します。

候補Gemを `candidate/ap2_mandate_verifier-1.5.0.gem`、任意driverを `candidate/sqlite3.gem` に置きます。driverは公式RubyGemsのsqlite3=2.10.2ネイティブ版で、実行platformと一致させてください。ホストへのインストールは不要です。

| Linux platform | 公式Gem | SHA256 |
| --- | --- | --- |
| ARM64 | sqlite3-2.10.2-aarch64-linux-gnu.gem | `e9aea2c2b3476fc875dd8a89313a9a2862818519c0186bfb5b56d6f57bb08d98` |
| x86_64 | sqlite3-2.10.2-x86_64-linux-gnu.gem | `ca92731ab464df9cae503fa1a439a549e2724f6953c8c05a7769b59366e38f15` |

通常デモimageを先に用意したARM64例です。x86_64ではdriverと`SQLITE_SHA256`を上表に合わせます。

```sh
docker build --network none -f Dockerfile.replay-candidate \
  --build-arg CANDIDATE_SHA256=9fdd419d031ff10b17c5a9bf31afc74a5f03a70cdcb442d7b4c561f6f90f1802 \
  -t ap2-replay-candidate:local .
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-replay-candidate:local timeout 120 ruby examples/payment_acceptance_candidate.rb
```

例は初回予約と、再署名した同一業務操作の再送を比較します。開始handleは一つだけ、再送はTicketなしの既存状態です。模擬dispatch後の応答消失をunknownとして保存し、同じDBを開き直してprocessor照会用keyを取得し、元のClosedに結合した遅延Receiptで復旧します。Receipt成功は外部決済確定の証明ではありません。

このCLIは合成一時DBを作成して終了時に削除します。本番で一時DB・worker別DB・起動時の無条件再作成を使ってはいけません。全worker共通の保護された永続DB、独立した承認済みoccurrence、最新Host情報と原子的な開始CAS、processorの冪等性／照会／復旧が必要です。timeoutやError Receiptで自動解放しません。全Mandateを一律一回限りとはせず、別途承認した新occurrenceでは新しいClosedを使います。任意UUIDは承認ではありません。

同じ操作への再署名・改変条件・並行要求・強制終了・再起動を独立試験で扱います。SQLiteは単一hostの参照adapterであり、分散DB・backup rollback・filesystem障害・実決済のexactly-onceを保証しません。[API・状態・アプリ側の責務](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/PAYMENT_ACCEPTANCE.md)。候補は 160,256 bytes、SHA256 `9fdd419d031ff10b17c5a9bf31afc74a5f03a70cdcb442d7b4c561f6f90f1802`。両対応MRIの全回帰・集中84項目・独立process/crash95項目で確認しています。公開はOwner判断待ちです。
