[English](LOCALIZATION.md) | [日本語](LOCALIZATION.ja.md)

# 多言語対応: 動作・保守・互換性

通常のブラウザデモとA2A × AP2購入画面は、既存の業務処理を共有しながら**英語（`en`）と日本語（`ja`）**に対応します。既定は英語です。本書は実装の契約と検証方法を説明し、全環境ですべての検証を実行済みと主張するものではありません。

## 言語選択と表示だけの画面遷移

- 明示的な`locale`パラメータをセッション設定より優先します。`en`と`ja`だけを受け付け、未選択・未対応・不正な形式は`en`にします。
- コントローラはリクエストを`I18n.with_locale`で囲み、終了後は元のlocaleに戻します。別リクエストにも影響するプロセス全体の言語設定は変更しません。
- ナビゲーション・フォーム・リダイレクトURLに選択言語を含めます。後続リクエストでパラメータが省略されてもセッションで維持します。
- ページの`lang`、ナビゲーションラベル、通知、アプリの入力エラー、結果説明は選択言語を使います。言語リンクの名前は **English / 日本語** のままです。ブラウザ標準の必須入力の吹き出しはブラウザ／OSの言語に従います。アプリの翻訳対象とは別で、サーバー側の同意・CSRFエラーは翻訳します。
- 言語リンクは表示ページへの安全なGETです。承認・実行・復旧の操作先には向けず、状態照会や再実行のフラグも付けません。

### 通常デモの結果snapshot

`DemoController`は、上限 **16 MiB・プロセス内のRails MemoryStore**に、**有効期間30分**の表示snapshotを保存します。セッションcookieは不透明なsnapshot IDだけを持ち、署名文書を含みません。検証POSTは結果GETへリダイレクトします。販売者署名と複数明細の言語リンクは`view=1`を含み、保存済み結果だけを読みます。通常の再読み込みも、同じセッションとプロセス内cacheが有効な間は保存済み結果を再利用し、署名・hash・診断・Receipt結果を維持します。

`view=1`を含む言語／表示URLは、期限切れ・cacheからの除去・欠損があってもsnapshotを再生成せず、明示的な実行を求めます。この保証は販売者／複数明細のすべてのURLには適用されません。サーバー再起動によってセッションが無効になった場合や、ほかの理由でセッションを失った場合、`/merchant`や`/multi-item`を直接開く／再読み込みすると、初回訪問として合成デモを再実行します。`run=1`を含む明示的な再実行URLも、再読み込みすると再実行します。保存済み結果だけを確認したい場合は言語／表示リンクを使ってください。

これは文書化した**単一プロセスのローカルデモ**向けであり、永続化や複数worker間の共有結果サービスではありません。サーバー再起動で消えます。以前の検証結果の表示は、最新の注文状態・現在の承認・新たな実行許可を示しません。

### 購入summary

購入画面と履歴は、現在のブラウザセッションが所有する保存済みsummaryを読みます。**状態を更新**は明示的にサービスへ照会します（`refresh=1`）。通常の遷移・再読み込み・言語切替はAgent照会・承認・購入実行・復旧を行いません。**Agent実行／同じ購入を再実行**と**保存済み結果で復旧**は、引き続きCSRFで保護された別操作です。

元の購入ID・承認条件・提示・模擬実行回数・署名文書は表示言語から独立しています。リクエスト単位の言語処理によって、所有確認・明示同意・CSRF・機密情報の除外・replay防止を弱めません。

## 翻訳の保存先

| 対象 | ファイルとキーの名前空間 |
| --- | --- |
| 通常画面 | `config/locales/demo.en.yml`、`config/locales/demo.ja.yml`、`demo.*` |
| 購入画面・動的結果 | `purchase_demo/locales/en.yml`、`purchase_demo/locales/ja.yml`、`purchase.ui`、`scenarios`、`stages`、`statuses`、`reasons`、`flash` |
| 購入表示の安定コードと旧データ互換 | `purchase_demo/summary_codes.rb` |
| 通常画面のlocale回帰テスト | `test/demo_locale_test.rb` |
| 購入locale・旧データのテスト | `test/purchase_locale_test.rb` |

各アプリは両言語で同じERBテンプレートを使います。通常サービスの結果は安定した`title_key`／`reason_key`を持ち、SDK診断は機械判読用フィールドを変えずに各言語で取得します。購入summaryは`receipt_success`、`not_started`、`response_timeout`などの安定コードを持ち、viewで表示文言へ変換します。

## 翻訳を追加・更新する

1. 同じ意味のキーを両言語のファイルへ追加します。`%{quantity}`、`%{amount}`、`%{currency}`などの補間名をそろえます。
2. 共有テンプレート／コントローラで既存のI18n helperを使います。言語で語順が異なる断片を連結せず、文全体をcatalogへ置きます。
3. 業務判断は文言から独立させます。新しい購入状態・理由が必要なら`SummaryCodes::STATUS_CODES`または`REASON_CODES`へ安定コードを追加し、両言語の翻訳とテストを加えます。翻訳文字列の比較で開始や再実行の可否を判定しないでください。
4. 人が読む商品名は表示層だけで翻訳します。商品ID・数量・金額・通貨コード・承認条件・シナリオID・機械判読用診断は維持します。
5. 署名付きMandate／Receipt、SD-JWT／JWS原文、プロトコルのキー・値、hash、ID、保存済みproof bytesを翻訳・書換えしません。翻訳の代わりに機密情報や未知の生エラーを表示しないでください。
6. コマンド・ポート・機能・手順が変わったら、両READMEと対になるQuick Start／購入ガイドを更新します。コードブロックを同期し、日本語のみの歴史資料には言語を明示します。
7. localeと既存回帰のテストを実行し、両言語をPC・狭いスマートフォン幅で確認します。長い英語が折り返され、操作部品や通貨が隠れないことを確かめます。

**AP2検証**、**アプリの実行判断**、**模擬決済の結果**、**Receipt確認**を一貫して使います。検証成功やReceiptの真正性だけを決済成功とは表現しません。結果不明は不明のまま、真正なErrorは失敗のまま扱います。

## 既存の日本語保存データ

多言語化のための破壊的なmigrationやvolumeリセットは不要です。

- `SummaryCodes`は、以前出力した日本語の状態・理由と安定コードの完全一致mapを持ちます。読取り時は表示・比較用の**コピー**を正規化し、表示のために保存データを書き換えません。
- 新たに生成するsummaryの状態・理由は安定コードです。業務判断は翻訳文ではなくコードとプロトコル状態を使います。既存の判定に関わる既知の旧値は正規化し、更新後も動作を維持します。
- 未知の旧自由文は、各言語の保守的な案内に置き換えて表示します。部分一致から推測したり、成功として扱ったり、信頼しない診断原文として出したりしません。保存された元の値は残します。
- 承認・提示・Mandate・Receipt・wire・hash・台帳の原文は翻訳しません。通常の承認済み操作は従来どおりsummary状態を更新しますが、表示や言語切替は更新しません。
- 更新前のセッションに残る未表示のflash通知も、既知文言の完全一致mapと現行コードの許可リストで変換します。未知の文字列は原文を出さず、各言語の代替案内にします。一度のリクエストで通知を消費する通常動作は維持し、通知の翻訳で購入データを書き換えません。

別の旧値へ対応するときは、確認済みの完全一致mapとfixtureテストだけを追加してください。DB内の日本語を一括置換しないでください。両言語の表示を試し、読取り・翻訳が保存済みrecordや署名原文bytesを変えないことを確認します。

## 自動検証

最終sourceでimageをbuildしてからテストします。通常・購入それぞれの検証スクリプトに、localeテストと既存回帰テストが含まれます。

```sh
# Standard image: existing regressions plus locale behavior and catalog checks.
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-mandate-verifier-demo:local timeout 900 sh test/docker_validation.sh normal
# Focused standard locale tests.
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-mandate-verifier-demo:local timeout 120 bundle exec ruby test/demo_locale_test.rb
# Purchase stack must be running. This creates synthetic purchases and restarts agents.
sh test/purchase_docker_validation.sh
# Focused purchase locale tests in the running authority container.
docker compose -f compose.purchase.yml exec -T authority \
  timeout 120 bundle exec ruby test/purchase_locale_test.rb
```

通常imageの検証、通常localeの個別検証、稼働中購入構成の全体検証、購入localeの個別検証の順です。購入全体検証は合成購入を作成し、Agentを再起動します。

catalogのキーと補間の一致、英語への日本語残り（言語リンクを除く）、成功・拒否・エラーの翻訳、既定／fallback／維持、別セッション・別スレッド、既知／未知の旧データの読取りを確認します。localeテストでは、言語／表示リンクと同じ有効なセッション内での再読み込みが検証や購入の副作用を呼ばず、ID・金額・コード・結果を維持することも確認します。通常デモの初回訪問と明示的な再実行URLは、前述の別の動作です。UIの個別テストを実TLS・A2A・timeout・並行実行・再起動の代わりにはしません。

## ブラウザ確認と証拠

1. 通常デモの両言語: 四つの検証、販売者Success／Error、複数明細の正常／数量不足を確認し、状態・コード・Evidenceを区別します。
2. 購入デモの両言語: 八つのシナリオ、明示同意、同意なし、古い／不正フォーム、結果、状態更新、復旧、所有確認済み履歴を確認します。
3. 日本語で送信し、リダイレクト後に英語へ切り替え、再読込み・履歴移動・戻る／進むを試します。同じID・条件・元の結果・実行回数を確認します。完了済みの同じ購入を再実行し、模擬実行が1回のままであることを確認します。
4. timeout後、復旧前に言語を切り替えます。結果不明のままで、新しい承認やdispatchがないことを確認します。同じ保存済み結果を復旧し、元Receiptと実行回数1を確認します。
5. 日本語選択後に未対応localeを指定し、英語fallbackを確認します。二つのセッションで違う言語を使い、互いに混ざらないことを確認します。
6. PCと約 **390 × 844** のスマートフォン幅で、keyboard focus・長いラベル・ページの`lang`・ナビゲーションラベル・USD／JPYの明示を確認します。機密値が出ないことも確認します。
7. 実装が変わったら影響する確認を繰り返します。正確なrevision／環境、成功・失敗・未実行、画像の保存先を記録します。過去の成功を現在のcommitの成功とみなしません。

今回の環境と結果は[多言語化の検証記録（英語／日本語）](LOCALIZATION_VALIDATION.md)に記録します。以前の証拠は[購入検証（英語）](PURCHASE_VALIDATION.md)、[公開Gem検証（日本語）](PUBLISHED_160.md)、[Docker対応環境（英語／日本語）](DOCKER_PORTABILITY_160.md)に残します。最終remote commitのチェックと独立レビューはPRに記録します。
