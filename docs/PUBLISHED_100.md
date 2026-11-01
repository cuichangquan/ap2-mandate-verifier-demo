# 公式1.0.0へのデモ更新と新規検証

開始main `41db1fcbf95ec62ce890980747470730a93f821d`、開始時open PR0。
Ownerの2026-11-01 18:52 JST依頼に基づく、デモrepoだけの更新です。
通常Gemfile/lock/Dockerfile、README、導入payload検査を1.0.0へ揃えます。
本体1.0.0実装・文書・tag/Releaseは他タスクで完了しており、変更しません。

## 公式Gemと1.x互換性

公式公開日時2026-11-01 08:13:29.733 UTC、102,912 bytes、SHA256
`a107101b0178c54ba417be7a2bd7e22feb2fd9a07bda089043e8c5ea8e65e12b`。
公開source `59e344ad865ed867d0993120456f9411d82bcdec`、tree
`4d72878e73656733b577d55529acc55cb7af6d5b` をGitHub APIで確認。
公式metadata・download SHA/size・全33archive/source payloadを新たに照合しました。
同じ公式Gemを通常導入し、Gemの再build/repushは行いません。

[1.x公開API](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/PUBLIC_API.md)と
[0.8.0からの移行](https://github.com/cuichangquan/ap2-mandate-verifier#upgrading-from-080)を確認。
1.0.0は0.8.0の実装・公開API・profile/hash・既定値・InputBuilder保存形式・
Result/Evidence/診断/Receiptの意味を維持します。`verified_research`等の名称も変更なし。
デモで使う公開APIとprofile定数は1.x契約内で、アプリソース変更は不要です。
依存宣言を旧0.8.0固定から1.0.0固定へ更新しました。他依存の版/制約/checksumは不変で、
lock差分はVerifier版2箇所とchecksum1箇所だけです。

## Fresh buildと導入後payload

```sh
docker build --platform linux/arm64 -t ap2-published100-demo:post .
```

既存公式Ruby4.0.9 base digestとBundler4.0.20を維持。Verifier版変更で新たに
公式Gemを取得しsize/hashを検査、同じbytesをBundler cacheへ渡します。
`BUNDLE_FROZEN=true bundle install`、resolved lockと元lockのbyte一致が成功。
`test/installed_gem_check.rb`は公式archiveのSHA/size・name/version・全33ファイルと
通常installed payloadのbyte一致・依存5件・Ruby要件・source外のGemロードを確認。
build時にも実行するため、不一致で通常導入を成功扱いしません。

最初のbuildは既存ignoreが`/scripts/`を除外していたためCOPY前に停止しました。
除外設定を緩めず、検査helperを既存test配下へ移して修正。失敗はローカルの
build準備であり、CI失敗/再実行ではありません。最終image IDはPR証拠コメントへ記録。
文書追加前後でruntime/app/configは同一です。

## 新規実測（過去の0.8.0 PASSを流用しない）

Fresh公式1.0.0 image、network無効、1CPU/512MiB/PID128で確認：

| 検査 | 結果 |
| --- | --- |
| 公式Gem SHA/size・33archive/installed payload・frozen lock | PASS |
| 通常4ケース・診断・CSRF・独立Host入力 | 7 tests / 173 assertions PASS |
| Merchant署名・真正Success/Error | 1 test / 13 assertions PASS |
| 複数明細成功・後続数量不足・表示 | 3 tests / 35 assertions PASS |
| 既存suite合計 | 11 tests / 221 assertions、failure/error/skip0 |
| インストール済みGem内のRuby単体条件委任例 | PASS、3明細・候補選択・Success/Error |

専用`127.0.0.1:3110`とChrome実フォームで1.0.0表示、正常Evidenceあり、改ざん
`host_binding_mismatch`、期限切れ`invalid_purchase_time`、通貨欠落
`invalid_host_context`と`order.currency`診断、各拒否Evidenceなしを確認。
`/merchant`でSuccess/Error真正性true、Error購入成功false・期待issuer違いfalse、
`/multi-item`でCoffee2/Tea3・480成功、Tea2・400の`constraint_mismatch`と
Evidenceなし、真正なSuccess/Errorを確認し、表示も目視検査しました。
専用tab/containerは確認後に終了。共有image/cache・他サービスは削除/停止しません。

## 範囲と統合条件

Ruby単体SDKの実行例を主導線に維持します。Rails UIは既存の合成Open→Agent Closed検証、
販売者署名・Receiptシナリオで、Direct/条件承認・Open発行・Agent Closed生成UIは
追加しません。本人認証・同意・購買権限・登録trust・鍵管理・DB永続化・原子消費・
注文/決済実行・結果不明の照会は利用アプリの責務です。
EvidenceやReceipt真正性は購入/決済許可・完了を意味しません。

歴史的0.6.0比較用Gemfile/lock/Dockerfileの動作は維持し、通常1.0.0へ混ぜません。
既存app/services/画面/3suiteと固定fixtureは変更なし。新規検査helperは導入状態のみを検査。
repoにActions workflowはなく、Draft PR・最新HEAD独立Codexレビュー・実質指摘解消・
未解決thread0・必要試験・現行保護条件成立後のみ条件付きSquash Mergeします。
Owner代理approval review、bypass、保護変更は行いません。

NOT_RUN：Gem build/repush、本体/Release変更、歴史的候補build、デモMRI3.4.12や他OS/arch、
最悪性能/並行負荷、host新規導入、追加費用、security/credential変更、実Issuer/実決済、
公開Web/production deployment。実際の最終PR/HEAD/review/image refsはPR証拠記録へ保存します。
