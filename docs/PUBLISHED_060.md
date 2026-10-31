# 公式0.6.0による公開後デモ検証

2026-10-31 UTCの新規実測。公開前候補の結果を今回のPASSへ転載していません。
開始mainは `6da8bfe27e19600aec535a144da58b3bfdb8c8c4`。
この変更は通常Gemfile／lock／Dockerfileと公開状態の表示・案内を更新し、
Verifier実装・固定依存版・旧profile・合成発行／業務責任の境界を変えません。

## 公開物と導入

公式Gem `ap2_mandate_verifier` **0.6.0**、**56,832 bytes**、SHA256
`ff669a62717f91b2295b3cea1b68c6c4143c490d98df071fd322ad4b0007195d`。
公開sourceは `baee59a603d08123adc0af50e57c8710ea62f4f9`。
DockerfileはRubyGemsから取得したこのbytesを検査してBundler cacheへ渡し、
`BUNDLE_FROZEN=true bundle install`で通常導入します。Gemのbuild／再pushはありません。
lock差分はVerifierのversion2箇所とchecksum1箇所のみで、Rails等の固定依存は不変です。

fresh buildは既存公式baseを使用して次を実行しました。

```sh
docker build --no-cache --pull=false --platform linux/arm64 \
  -t ap2-published060-demo:post .
```

imageは `sha256:8c92e822ccd884929e79c056cf12c720db4420d4f5c353e44d0ccc34230d5ec7`。
MRI4.0.9／aarch64-linux、Bundler4.0.20、OpenSSL library3.5.7。
導入後もGem cacheのsize/hash、`Gem.loaded_specs`の0.6.0、
`cmp Gemfile.lock /tmp/resolved-Gemfile.lock`の一致を確認しました。

最初のbuild呼出しはbuildx非対応の `--cpus` 引数により**build開始前に停止**。
その引数を除いてfresh buildが成功しました。依存・署名・checksum検査を緩めていません。
build中の総通信量・ピークCPU／RSSは未測定です。

## 今回の実測結果

テストは上記fresh imageで、`--network none --cpus 1 --memory 512m --pids-limit 128`。
README掲載の3suiteを各120／60／60秒上限で実行しました。

| 観点 | 結果 |
| --- | --- |
| 通常4ケース、診断、CSRF、独立Host入力 | PASS: 7 tests / 173 assertions |
| Merchant署名・真正Success/Error Receipt | PASS: 1 test / 13 assertions |
| 複数明細成功・後続数量不足・公開済み表示 | PASS: 3 tests / 35 assertions |
| 合計 | PASS: 11 tests / 221 assertions、0 failures/errors/skips |
| 実Chrome画面の通常フォーム | PASS: 正常／改ざん／期限切れ／通貨欠落のstatus/code、診断、Evidence |
| 実Chrome画面 `/merchant` | PASS: 両Receipt真正性true、Success購入成功true、Error購入成功false、別署名者false |
| 実Chrome画面 `/multi-item` | PASS: Coffee2／Tea3、合計480で成功・Evidenceあり。Tea2、合計400でもconstraint_mismatch・Evidenceなし。真正Success/Errorも確認 |

実画面は今回の公式Gem imageを `127.0.0.1:3106` に限定して一時起動し、
通常フォームを実送信して確認しました。旧profile名と0.6.0表示、新profile明示選択を確認。
専用Chromeタブと専用preview containerは検証後に終了しました。
共有サービス・image・cacheは削除していません。

## 範囲と未実施

`Dockerfile.candidate`／`Gemfile.candidate`はローカル開発source比較用に区別して残します。
今回の公開後整備ではそのbuildを実行していません。公開前の観測は
[候補の歴史記録](MULTI_ITEM_CANDIDATE.md)で保持します。

他OS／architecture、RailsデモのMRI3.4.12、最悪時性能／並行負荷はNOT_RUN。
実Issuer・実運用鍵・実利用者情報・nonce消費・実決済・本番GO・公開Webデプロイは対象外です。
Macへの新規導入、追加費用、Issue作成／再試行は行っていません。
