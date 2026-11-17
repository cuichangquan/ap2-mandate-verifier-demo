# Payment診断：表示された結果からRubyコードへ

公開後の通常経路は1.7.0です。以下の候補専用Dockerfile・手順は公開前の基準commit `e3fbb0eba4891ad7bb74112fdd3a0dafa18aed55` に残す再現記録です。1.7.0の通常イメージへ重ねず、再現するときだけそのcommitの別checkoutで使ってください。今回の公開版切替と検証上の制約は末尾に記録します。公開やデプロイは別の操作です。

[English](PAYMENT_DIAGNOSTICS.md)

今回の対象はIssue #35の **A3** です。完了済みA1（組み込み例・復旧手順）、A2（起動待ち・TLS保守）を作り直すものではありません。
AP2検証、アプリの実行判断、模擬決済、Receipt検証の4段階を維持します。

結果画面には従来のstatus・理由コードに加え、記録できたGem診断の処理名・段階・理由・項目・日英の確認事項を表示します。「この処理のRubyコード」を開くと、seller.rb・buyer.rb・protocol.rbに対応する短い例を読めます。コードの開閉、言語切替、保存履歴の再表示は購入や復旧、購入状態照会を実行しません。
通常経路は公開版1.7.0の診断APIを使います。古い1.6.0の保存結果には追加診断がない場合があります。診断がないことは成功・失敗の根拠になりません。

## Gemの事実とアプリの案内

```ruby
started = service.start_with_diagnostic(ticket: accepted.ticket,
  verification_inputs: verification(fresh, wires))
execution = started.execution # Executionまたはnil。再試行の許可ではない
checked = AP2MandateVerifier::PaymentReceipt.verify(jwt: receipt,
  closed_sd_jwt: saved_closed, **trusted_context, verified_at: now)
checked.verified?          # 真正性と参照関係
checked.payment_succeeded? # 真正なErrorは検証成功だが支払い成功ではない
checked.diagnostic        # nilの場合もある。再決済の許可ではない
```

例では信頼情報の取得、永続保存先の作成、保存済みchallenge、現在の注文・時計、エラー処理、模擬決済処理を省略しています。実際の役割別メソッドも確認してください。
`start_with_diagnostic`と従来の`start`はどちらか片方を一度だけ呼びます。診断表示のために処理を再実行しません。

役割間通信と保存ではGemカタログの識別子だけを扱い、任意の説明文・未知の識別子・例外全文・入力値を除去します。表示時にインストール済みGemのカタログから説明を復元します。これは診断自体の真正性を証明する仕組みではありません。診断の欠落は既存判定を変更しません。
通信タイムアウトはアプリの観測であり、Gemが原因を確定したようには表示しません。結果不明、nilの実行ハンドル、真正なErrorを、自動再決済や利用枠解放の根拠にしないでください。

## 過去の公開前候補を使う経路（公開前checkout専用）

通常のGemfile・lockfile・公開Gemチェックサムは変更しません。
本体候補レポートのソースcommit・版・バイト数・SHA256と**同一のGemファイル**を使います。再ビルドした場合は再検証が必要です。

1. 通常イメージを作成：`docker build -f Dockerfile.purchase -t ap2-purchase-demo:local .`
2. 候補を`candidate/payment-diagnostics.gem`へ配置（git管理対象外）。
3. 記録された値で候補イメージを作成：

```sh
docker build -f Dockerfile.payment-diagnostics \
  --build-arg CANDIDATE_VERSION='<版>' \
  --build-arg CANDIDATE_BYTES='<バイト数>' \
  --build-arg CANDIDATE_SHA256='<SHA256>' \
  -t ap2-purchase-diagnostics:candidate .
```

候補専用イメージ内でファイルのバイト数・ハッシュ・Gem名・版を検査し、実際にGemをインストールします。イメージ内のGemfile・lockfileだけを変更し、固定依存関係と読み込み元を検証します。依存関係の変更が必要なら候補設定をレビューし直します。
既存の起動済みデモや保存ボリュームを使わず、新規Compose projectで起動します。

```sh
COMPOSE_PROJECT_NAME=payment-diagnostics-qa PURCHASE_UI_PORT=3117 \
  PAYMENT_DIAGNOSTICS_IMAGE=ap2-purchase-diagnostics:candidate docker compose \
  -f compose.purchase.yml -f compose.payment-diagnostics.yml up -d --no-build
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-purchase-diagnostics:candidate timeout 120 bundle exec ruby \
  test/purchase_diagnostics_runtime_test.rb -n /test_diagnostics_/
```

通常公開版CIは別途実行します。候補とデモのcommit、nativeアーキテクチャ、Ruby版、試験結果・未実施事項を記録します。プロセス内の役割連携試験はHTTPS、ブラウザの見た目、native ARM64の検証ではありません。

## 公開版1.7.0への切替

本人承認の切替では、通常Gemfile・lockfile2種、Dockerfile2種、インストール済みGem監査、公開版のRuby例、現在版の日英説明を更新します。
公開Gemは208,384 bytes、SHA256 `2a3da0706313fd6ef6bf05dd0aed2f05899a5690b42568b3ebd814b41ad17140`で、レビュー済み候補と一致します。
通常イメージ2種とも配布ファイルとインストール済み75ファイルを照合し、ソースcheckoutや再ビルドで代用しません。過去候補と検証履歴は変更しません。

統合前に、切替commitに対する既存のnative ARM64/AMD64 CIを通す必要があります。公開Gemの実インストール、診断、英日画面、HTTPS購入・復旧を確認します。現在の結果はPR #39で確認し、過去候補の成功と混同しないでください。
ドラフト更新はマージ・デプロイ・起動済みスタックの置換ではありません。このデモ変更でタグ・GitHub Release・Gem公開も実施しません。
