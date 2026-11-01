# 公式0.7.0による公開後デモ検証

2026-11-01 UTCの新しい測定です。開始mainは
`37ba736ebb32742f17d793d74c196a4ea723ce63`。Ownerは公開済み0.7.0への通常起動、
案内、fresh build／検証、独立レビューと条件付きSquash Mergeを承認しています。
Gemfile／lockのVerifier版とchecksum、Docker download検査、READMEを更新し、
既存の単品／診断／販売者署名／複数明細シナリオは変更しません。

## 公式Gemとfresh build

0.7.0、64,000 bytes、SHA256
`baab8c68355b5e6c9351e7d86a836fab50652cdad662bbc99d1676c5e6134447`。
公開source `9b4b78a7ed9aa95e7d35e01a64efc1281ba95be3`、
公開日時2026-11-01 03:12:46.522 UTC。公式Gemを検査してBundler cacheへ渡し、
`BUNDLE_FROZEN=true bundle install`で通常導入。Gemをbuild／再pushしません。
最終lock差分はVerifier版2箇所とchecksum1箇所だけです。

```sh
docker build --platform linux/arm64 -t ap2-published070-demo:post .
```

変更したGemfile/lockにより依存導入層が新たに実行され、checksumとfrozen導入が成功。
image SHA256は `b0a59186ef179b5425766c59db3ff842aa830c13c5f5f4ca72a37f1ba4cf6485`。
既存公式base digest、MRI4.0.9、Bundler4.0.20は維持。
導入後のGem cache size/hashと`cmp Gemfile.lock /tmp/resolved-Gemfile.lock`も一致しました。

準備中に版文字列の一括置換がIRB配下の`pp >= 0.6.0`まで`>= 0.7.0`へ変更し、
frozen buildが停止しました。実Gem（固定checksumのIRB1.18.0）から本来の依存宣言を
確認し、置換前へ戻しました。最初の復元copyは相対path誤りで反映されず同じ停止に
なりましたが、絶対pathで復元後の新buildは成功。依存版／checksum／frozen条件の
緩和はありません。失敗はローカルbuildで、GitHub CIの失敗rerunではありません。

## 実測

既存READMEの3suiteをoffline・1CPU／512MiB／pids128で実行：

| 試験 | 結果 |
| --- | --- |
| 通常4ケース・診断・CSRF・独立Host入力 | 7 tests / 173 assertions PASS |
| Merchant署名・真正Success/Error | 1 test / 13 assertions PASS |
| 複数明細成功・後続数量不足・表示 | 3 tests / 35 assertions PASS |
| 合計 | 11 tests / 221 assertions、failure/error/skip 0 |

専用previewを`127.0.0.1:3107`に限定しChromeで確認：0.7.0表示、通常フォームの
正常（Evidenceあり）、改ざん（host_binding_mismatch）、期限切れ（invalid_purchase_time）、
通貨欠落（order.currency診断）、各拒否Evidenceなし。`/merchant`で両Receipt真正性true、
Error購入成功false・別署名者false。`/multi-item`でCoffee2／Tea3・480成功、Tea2・400の
constraint_mismatchとEvidenceなし、真正Success/Errorを確認しました。
専用タブとpreview containerは検証後終了。共有image／cache／他サービスは削除しません。

## 範囲

このUIは既存Open→Agent Closedの合成デモで、Direct本人承認UIではありません。
0.7.0 Direct APIの完全実行例と責任境界はREADMEから本体の公式例へ案内しています。
本人認証・購買権限・Provider鍵登録・保護された承認記録・永続一意制約／原子処理・
結果不明時の照会はアプリ責任。受理やReceipt真正性は実購入／実決済成功ではありません。
他OS／architecture、デモのMRI3.4.12、最悪性能／並行負荷、実Issuer／実鍵／実決済／
公開Web／本番運用はNOT_RUN。ホスト導入・追加費用・security設定変更なし。

## 独立レビューによる比較経路の是正

GitHub Codexが最新HEADで、旧0.6.0比較用Gemfileと通常0.7.0lockの共有による不整合を
P2として指摘しました。旧mainのlockを正確に`Gemfile.candidate.lock`へ分離し、
`Dockerfile.candidate`の初期COPY先をそちらへ変更。0.6.0比較経路の契約を保ち、
通常0.7.0経路へ混ぜません。既存0.6.0imageで専用Gemfile/lockの
`BUNDLE_FROZEN=true bundle check`がoffline成功。指摘を是正し最新HEADへ再レビューします。
候補Gem buildは今回の禁止範囲なのでNOT_RUNです。通常デモとその試験経路は変更しません。
