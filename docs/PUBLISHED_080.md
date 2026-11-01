# 公式0.8.0による公開後デモ検証

開始main `58d9db187af51a70d2439ff30cf8a0613ae3d7f0` からの新しい測定です。
Ownerは公開済み0.8.0への通常起動・文書・fresh build／試験／実画面確認、
独立最新HEADレビューと条件付きSquash Mergeを承認しました。
Gemfile／lockのVerifier版2箇所とchecksum1箇所、Dockerの版・size/hash検査、
READMEの導入例を更新。アプリ／service／既存test／他依存は変更しません。

## 公式Gemと導入

公開06:01:31.103 UTC、source `5a7394c1b98f000b321423e2c2f80d50b5157808`。
79,872 bytes、SHA256
`6c07664e4291aa8bc025b152075869322411a0d99861e1267959f1794e99acec`。
公式downloadを検査してBundler cacheへ渡し、`BUNDLE_FROZEN=true bundle install`。
導入済みGem cacheのsize/hash、lockとresolved lockのbyte一致も確認しました。
Gem再build／再pushなし。既存公式base digest、MRI4.0.9、Bundler4.0.20を維持。

```sh
docker build --platform linux/arm64 -t ap2-published080-demo:post .
```

Verifier版変更により依存導入層を新たに実行し、checksumとfrozen installが成功。
実測image IDは最終PRの証拠コメントへ記録します。文書追加前後でruntime/configは同一です。
準備時の限定置換で一時的にGemfile/lockへNULを入れたため、実行前のdiffで検出して
元HEADからその2ファイルだけ復元し、明示的なgem名の行だけを修正しました。
NUL状態でbuild/PR/pushはしておらず、他依存版・checksum・frozen条件の緩和なし。

## 新規実測

Fresh公式Gem imageをoffline・1CPU／512MiB／pids128で試験：

| 試験 | 結果 |
| --- | --- |
| 通常4ケース・診断・CSRF・独立Host入力 | 7 tests / 173 assertions PASS |
| Merchant署名・真正Success/Error | 1 test / 13 assertions PASS |
| 複数明細成功・後続数量不足・表示 | 3 tests / 35 assertions PASS |
| 合計 | 11 tests / 221 assertions、failure/error/skip 0 |

専用 `127.0.0.1:3108` previewとChromeの実フォームで、0.8.0表示、正常
`verified_research/scoped_research_verified`とEvidenceあり、改ざん
`host_binding_mismatch`、期限切れ`invalid_purchase_time`、通貨欠落
`invalid_host_context`と`order.currency`診断、各拒否のEvidenceなしを確認。
`/merchant`のSuccess/Error真正性true、Error購入成功false・別署名者false、
`/multi-item`のCoffee2/Tea3・480成功、Tea2・400の`constraint_mismatch`と
Evidenceなし、真正Success/Errorを確認し、画面表示も目視確認しました。
専用tabとcontainerは確認後に終了。共有image/cacheや他サービスは削除していません。

## 対応範囲

0.8.0の条件委任は[本体Ruby単体例](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/examples/conditional_checkout.rb)
を主導線にします。このRails UIは既存Open→Agent Closed検証とReceiptの合成デモで、
条件承認・Open発行・Agent Closed生成UI、本人認証、Provider鍵管理を実装していません。
SDKが対応した発行機能と、この画面が提供する機能を混同しません。
本人認証・購買権限・同意・登録trust・永続一意制約／原子消費・結果不明時の照会は
利用アプリ責務です。EvidenceやReceipt真正性は実購入／決済成功ではありません。

0.6.0の歴史的なsource比較Gemfile/lock/Dockerfile経路はそのまま維持し、通常0.8.0
lockへ混ぜません。比較候補のGem buildは今回NOT_RUN。
他OS/architecture、デモMRI3.4.12、最悪性能/並行負荷、実Issuer/実鍵/実決済、
公開Web/本番運用もNOT_RUN。ホスト導入・追加費用・security設定変更・credential作成なし。
RepositoryにActions workflowはありません。最新HEAD独立Codexレビュー・実質指摘解消・
未解決thread0・保護条件成立後のみSquash Mergeし、Owner代理approval reviewは提出しません。
