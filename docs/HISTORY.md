# 0.2.1までのデモ観測履歴

ここは0.1.0／0.2.0／0.2.1の過去の観測です。現在の0.3.0起動・検証手順は[README](../README.md)を参照してください。過去のPASSを公開0.3.0の実測として扱いません。

以下の画像は2026-10-30にGem0.2.1のfresh buildから起動した実localhost画面です。

![0.2.1の過去の概要画面](images/overview.jpg)
![0.2.1の過去の成功画面](images/verified.jpg)

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

