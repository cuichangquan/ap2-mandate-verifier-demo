# AP2 Mandate Verifier Demo

Ruby／Rails開発者が、購入委任の「検証成功」と「拒否の理由」をブラウザで比較できる、小さなローカル専用Railsアプリです。[ap2_mandate_verifier 0.2.1](https://rubygems.org/gems/ap2_mandate_verifier/versions/0.2.1) を実際に呼び、正常・改ざん・期限切れの3ケースを試せます。Gemを自分のアプリへ組み込む前に、返される結果と責任境界を確認できます。

実際の3ケースを画面とコードで紹介する[Zennの解説記事](https://zenn.dev/ccq/articles/7f9643f96fe5c7)も公開しています。

**検証成功・Evidenceは購入許可ではありません。** 実決済、注文更新、実Issuer連携、nonce消費や注文CASは行いません。

![日本語の購入委任検証デモ。3つのシナリオと、検証成功は購入許可ではないという警告](docs/images/overview.jpg)

## 3つのシナリオ

| 選択 | 成功・拒否の理由 | 実際のGem結果 | Evidence |
| --- | --- | --- | --- |
| 正常な購入内容 | 合成データが固定profileの検査を通過 | verified_research / scoped_research_verified | あり（検証事実のみ） |
| 購入内容を改ざん | 購入内容と保存済みHost情報が不一致 | rejected / host_binding_mismatch | なし |
| 有効期限切れ | 合成デモ時刻が有効期間の条件を満たさない | rejected / invalid_purchase_time | なし |

画面には日本語の結果・理由、Gemのstatus/code、Evidenceの有無、評価した合成時刻を表示します。エラーで検証を完了できない場合は「検証不能」とし、成功や購入許可として扱いません。

掲載する2画像は、2026-10-30にGem 0.2.1のfresh buildから起動したlocalhost UIを実ブラウザで撮影したものです。以下は正常ケースの実画面で、生成したモック画像ではありません。

![正常な合成データが実Gemの検査を通過し、Evidenceありと固定デモ時刻1800000000を表示する画面](docs/images/verified.jpg)

入力は保存済みの**合成fixture**です。信頼情報・注文・公開鍵もテスト専用で、実Issuerの信頼を示しません。現在時刻は使いません。

- 通常の評価時刻: Unix秒 `1800000000`。
- 期限切れの評価時刻: `1800000101`。署名済みmandateの期限は `1800000100`。
- 改ざんは購入JWTの単価を100から999へ変更し、元署名とHost bindingを維持します。Host bindingで先に拒否される例です。

アプリが受け付けるのは固定の3つのscenario識別子だけです。任意token、秘密鍵、URLの入力・取得はありません。

## Dockerで起動

GitとDocker DesktopまたはDocker Engineを用意し、以下のclone → build → runで起動します。DB・Redis・秘密鍵の準備や、ホストOSへのRuby／Gemのインストールは不要です。

この手順はLinux arm64/v8のイメージを固定して使います。2026-10-30にGem 0.2.1で公開Dockerfileを変更せず、アプリの依存build cacheを使わないfresh buildを1回確認しました（固定base layerは再利用）。MBA／Linux arm64の一構成に限る機能観測で、他architectureでの動作は未検証です。cloneの端末依存の制約、実行条件と未証明事項は「テストと実測範囲」を参照してください。

初回のビルドは公式Docker HubとRubyGems/CDNからイメージと依存を取得し、native extensionをビルドする場合があります。ネットワーク接続と追加ディスクが必要です。Gemfile.lockの固定条件を緩めず、取得・依存・providerの失敗時は停止してください。

```sh
git clone https://github.com/cuichangquan/ap2-mandate-verifier-demo.git
cd ap2-mandate-verifier-demo
docker build --platform linux/arm64 -t ap2-mandate-verifier-demo:local .
docker run --rm --name ap2-mandate-verifier-demo \
  --cpus 1 --memory 512m --pids-limit 128 \
  -p 127.0.0.1:3100:3000 \
  ap2-mandate-verifier-demo:local \
  timeout 3600 bundle exec puma -b tcp://0.0.0.0:3000 -t 1:1 config.ru
```

ブラウザで **http://127.0.0.1:3100/** を開き、正常 → 改ざん → 期限切れの順に選び、それぞれ「Gemで検証する」を押します。上の表と画面の結果・理由を比較してください。ホスト側の公開はlocalhostだけです。コンテナ内部のPumaは0.0.0.0:3000で待受します。最大60分で終了し、`--rm`でコンテナを削除します。

DB、Redis、バックグラウンドサービス、JavaScriptビルドは不要です。セッション署名値は起動時に一時生成し、再起動すると以前のセッションは無効になります。鍵を入力・保存する設定はありません。

早めに終了する場合は別ターミナルから実行します。イメージを再利用しない場合だけ最後のコマンドを実行してください。

```sh
docker stop ap2-mandate-verifier-demo
docker image rm ap2-mandate-verifier-demo:local
```

共有cacheやvolumeをpruneする必要はありません。

## テストと実測範囲

```sh
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-mandate-verifier-demo:local \
  timeout 300 bundle exec ruby test/demo_test.rb
```

2026-10-26のローカル検査で **3 tests / 82 assertions / 0 failures / 0 errors**。実Gemによる3ケース、反復と状態分離、安全なエラー理由、Evidenceの有無、フォーム、CSRF/Origin、Host制限、不明scenario拒否を確認しました。実HTTPとブラウザでも正常 → 改ざん → 期限切れ → 正常を確認しました。

初回ブラウザ確認でno-referrerによるnull Originの422を発見し、same-originへ修正して再テストしました。CSRF保護は有効です。公開準備時に固定のデモ署名値を一時生成へ置き換えました。

上記2026-10-26の検査は、既存のdigest固定Rubyイメージを使う取得コンテナ由来のイメージで行った履歴です。その時点では公開Dockerfileからのfresh buildは実施していません。

**2026-10-28の限定確認：** main [`7d77723`](https://github.com/cuichangquan/ap2-mandate-verifier-demo/tree/7d77723a1b4e4fdaee06f5b5293990935c317aeb) の公開Dockerfileを変更せず、`--no-cache`でfresh buildを1回（約67秒）、既存テストを1回実行し、**3 tests / 82 assertions / 0 failures / 0 errors**でした。ブラウザでも上の3ケースのstatus/codeとEvidence有無が表どおりであることを確認しました。実行環境はMBA上の既存Docker、Linux arm64、MRI 4.0.9／Bundler 4.0.20／Gem 0.1.0です。

- 固定base layerは再利用しました。RUN処理に2 CPU／2 GiBを指定しましたが、展開・転送等の共有daemon処理は上限外です。
- 全通信先・通信全量・ピークCPU/RSSは未計測です。通信条件の完全適合を確認した記録ではありません。
- provenanceのdigest差が未解明のままUI確認へ進めたSTOP判断の逸脱がありました。後に保存layerから公式式でlocal-image cache pinとの一致を確認しましたが、手順判断の問題や通信条件の未証明まで解消したとは扱いません。

これは当該環境での機能再現の記録です。実行条件全体の合格や、他OS/architecture・一般的な本番互換性、署名・SHA・依存の保証拡大を意味しません。

**0.2.0への更新（2026-10-30）：** 推奨API、依存version、公開archiveのサイズ/SHA256を更新しました。上記0.1.0のbuild・テスト・画面観測を0.2.0の実測として流用しません。既存のdigest固定base・保存済み依存archive・公開後に照合した0.2.0 Gemを使い、network noneの使い捨てコンテナでfrozenのoffline installと既存テスト1回を確認しました。**3 tests / 82 assertions / 0 failures / 0 errors**。fixture SHA・Gemの33,280 bytes/SHA・lock不変を確認し、1 CPU／512 MiB／PIDs128、全体600秒・テスト300秒、書込tmpfs合計512 MiBに制限しました。MRI 4.0.9／Bundler 4.0.20／OpenSSL gem 4.0.2・library 3.5.7での限定観測です。初回の誤ったlock置換と、次のtmpfs noexecによる準備停止は原因を記録・是正し、テスト本体は修正後に1回だけ実行しました。この時点ではfresh buildとブラウザ確認はNOT_RUNでした。後続の実測を次に分けて記録します。

### 0.2.0 fresh build・実ブラウザ確認（2026-10-30）

main [`18060d3`](https://github.com/cuichangquan/ap2-mandate-verifier-demo/tree/18060d32880a756432e704fd48f630cb715fff32) の公開Dockerfileを無改変で`--no-cache --pull=false` buildし、08:51:24–08:52:36 UTCの約72秒で成功しました。既存の固定base 7 layerを再利用し、WORKDIRはCACHED表示ですが、依存を取得・インストールするRUNは再実行されています。今回の端末ではcloneがGitのSSH転送／agent認証で失敗したため、公開main全17ファイルとGit blob一致を確認した保存sourceでbuildしました。cloneから一連の手順が完走したという記録ではありません。source取得前に誤って起動した準備buildはDockerfile未存在で即停止し、依存取得はありませんでした。

新しいimageで既存テストを1回実行し、**3 tests / 82 assertions / 0 failures / 0 errors**。Gem 0.2.0の33,280 bytes/SHA256、fixture SHA256、install後のlock一致を再確認しました。環境はLinux arm64、MRI 4.0.9／Bundler 4.0.20／OpenSSL gem 4.0.2・library 3.5.7です。localhostの実ブラウザで正常 → 改ざん → 期限切れを操作し、上表のstatus/code・Evidence有無、0.2.0表示、日本語の理由を確認しました。当時の画像はこのセッションで撮影した実画面でした。現在は次の0.2.1実測の画像へ更新しています。

- buildのRUNに2 CPU／2 GiBを指定し、15分・観測ディスク増加2 GiBを停止上限としました。build前後のホスト空き容量差は約127 MiBですが、他プロセスや共有daemonも含む観測値です。
- image内の取得archiveは44個・10,942,976 bytes。これは索引メタデータ・header・redirect等を含む通信全量ではありません。取得sourceはRubyGems、固定baseは公式Docker Hubを指定しましたが、全通信先・全量・CPU/RSSピーク・実cgroup値は未計測で、完全適合の証明ではありません。
- テストはnetwork none、テストとpreviewは1 CPU／512 MiB／PIDs128。previewはlocalhost限定、Puma 1 thread、08:53:36–08:54:51 UTCに使用して停止しました。専用container/imageは削除済みで、共有base/cacheは保持しました。

これは今回の一構成での機能観測です。他OS/architecture、実Issuer・実Host、鍵失効、性能・本番利用の確認や保証拡大は含みません。

### 0.2.1への追従と今回の確認（2026-10-30）

公開Gem 0.2.1はRuby 3.4.12対応を加えた保守版ですが、このデモはMRI **4.0.9**のままです。固定5依存・API・profile・Evidence契約は変えません。公式RubyGems APIのSHAと実配布Gem（34,816 bytes、下記SHA256）をinstall前に照合しました。既存main `5237824` の検証済みsourceを使い、Gem指定・archive照合値・画面versionだけを更新したDockerfileを`--no-cache --pull=false`で1回buildし、11:57:08–11:58:25 UTCの約77秒で成功しました。固定base 7 layerを再利用し、依存RUNは再実行されています。

新imageで既存テストを1回実行し、**3 tests / 82 assertions / 0 failures / 0 errors**。Gem/fixture SHA、install後lock一致を確認しました。Linux arm64、MRI 4.0.9／Bundler 4.0.20／OpenSSL gem 4.0.2・library 3.5.7です。localhostの実ブラウザでも正常・改ざん・期限切れが上表のstatus/code・Evidence有無どおりで、0.2.1表示・日本語の理由を確認しました。掲載2画像は今回撮影した実画面で、0.2.0の観測を今回の実測として流用していません。

buildのRUNは2 CPU／2 GiB、15分・観測ディスク増加2 GiBを停止上限とし、テストとpreviewは1 CPU／512 MiB／PIDs128、テストはnetwork none・300秒、previewはlocalhost限定・Puma 1 thread・最大3600秒です。取得archiveは44個・10,944,512 bytesで、メタデータ・header等の通信全量ではありません。公式Docker Hub/RubyGemsを取得元としていますが、全通信先・全量・CPU/RSSピーク・実cgroup値は未計測で、共有daemon処理はRUN資源制限の対象外です。専用container/imageは削除し、共有base/cacheは保持しました。

cloneは今回NOT_RUNです。前回のSSH agent認証拒否を変更・回避せず、既存の検証済みsourceを使いました。他OS/architecture、デモのRuby 3.4.12実行、実Issuer/Host、鍵失効、性能・本番は今回の確認に含みません。

## 固定した構成

- Ruby: MRI **4.0.9** 完全一致。
- Base: 公式 `ruby:4.0.9-trixie`、Linux arm64/v8、digest `sha256:42c18f0c9807ba1349c0253617d7f08ef98b815463b2f7785d97c4efdfd80f4d`。
- Rails components: railties/actionpack **8.0.4**。Puma **6.6.1**、Minitest **5.27.0**。
- Verifier: **0.2.1**。固定依存json **2.19.9**、jwt **3.3.0**、base64 **0.3.0**、openssl **4.0.2**、digest **3.2.1**を維持。
- ローカルで観測したBundlerは4.0.20、OpenSSL libraryは3.5.7。lockには複数platformの63 specs、実インストールは49 Gemsでした。

これは**Linux arm64・そのprovider・Railsの組合せにおけるデモ限定の実測**です。製品Gemの支持環境や保証を変更しません。製品の正確な対応範囲は[公式SUPPORT_CONTRACT](https://github.com/cuichangquan/ap2-mandate-verifier/blob/5a02bc3a192e16aa3628cf7899617623b0aed78c/docs/SUPPORT_CONTRACT.md)を参照してください。

Dockerfileは公開Gem archiveが **34,816 bytes**、SHA256が `a4ab7e0f6c9bd87355695369374f8e6e2dad104fb673700e9f616053afe6e114` であることをinstall前に照合し、チェックしたbytesをBundler cacheへ渡します。

## APIとfixtureの出所

`app/services/scenario_verifier.rb` が毎回新しいfixtureを読み、次の公開APIへ7入力を渡します。推奨APIを使い、旧verify APIや模擬成功結果は使いません。

```ruby
AP2MandateVerifier.verify_checkout(
  trust_json:, selection_json:, host_json:,
  root_presentation:, terminal_jws:, host_checkout_jws:, verified_at:
)
```

`verify_checkout`は`verify_research`と同じ検証への直接委譲で、入力の変換・補完は行いません。7 keyword、固定profile、Result/ResearchResult、Evidence v2の契約は変わりません。Evidenceは購入許可ではありません。

fixtureは[上流の固定commit](https://github.com/cuichangquan/ap2-mandate-verifier/blob/f6d4f83d396b75505256dba5769a54a8f065eeea/research/stage15/results/R3/INPUTS.json)のFULLのみを抽出しました。読み込み時にSHA256を確認します。

- 上流原本: `41ad845a7ea82a9c7316c9ef11fb8ee5281453afafe2b4932c7217c1936562c1`。
- 同梱full.json: `ac98f3b0c475365e2e7416cbb1838f1692a0ff2693c71dba0cb664c52b9ad42f`。

公開鍵と合成の署名済み入力のみを同梱しています。[MIT License](LICENSE)と[fixtureの出所・通知](THIRD_PARTY_NOTICES.md)を参照してください。ローカルログ、実行環境の機械情報、依存archive、セッション署名値はリポジトリに含めません。
