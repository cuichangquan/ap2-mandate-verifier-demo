# PISP・実行日時の条件 — 1.4.0候補

公開前の候補Gemで、PISPと日時条件を確認するRuby単体例です。通常Railsと公開版の例は1.3.0のままです。ホストへのRuby導入・本番デプロイ・実決済は不要です。

SDK候補を `candidate/ap2_mandate_verifier-1.4.0.gem` へ置き、検証済みSHA256を指定します。通常デモのDockerimageを先に用意してください。

```sh
docker build --network none -f Dockerfile.policy-candidate \
  --build-arg CANDIDATE_SHA256=ea82c6468f339ed280005e1a270a511b1a8594452ef3de6fb546de43aa6ba454 \
  -t ap2-policy-candidate:local .
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-policy-candidate:local timeout 120 ruby examples/payment_policy_candidate.rb
```

例はDirect・完全内容の条件付きPayment・SelectiveCheckoutとSelectivePaymentの組合せを実行し、PISP/実行予定時刻の正常照合、独立したPISPや時刻の不一致、期間外の拒否、Success/Error Receiptを確認します。新profileを明示し、旧1.xの既定profileは維持します。候補GemはDocker内へ通常インストールし、その同梱例を読み込みます。通常Rails画面へ未公開機能を混在させません。

法人名・ブランド名・ドメイン名の3項目を正確に照合しますが、文字列一致や署名だけでQWAC・実サービスの真正性を証明しません。アプリが独立して認証したPISPと実行条件を与える必要があります。実行日時は厳格なRFC3339の瞬間として比較し、両端を含む期間を扱います。`verified_at`はMandateの有効時刻、`execution_at`はアプリの独立した実行予定・運用時刻です。将来の計画照合は、実行完了や決済確定の証明ではありません。

PISP一覧と日時条件は選択的開示でも全表示です。隠せるのは従来の支払先・決済手段の候補だけです。PISPと決済手段の相関した承認は別Openで表現し、独立集合に勝手に広げません。完全Open・非選択候補・salt・秘密鍵を出力しません。すべてメモリ内の合成鍵・模擬条件です。同意・trust/失効・原子的nonce消費・最新注文・実決済・未知結果の回復はアプリ責任です。

[SDKのAPI・厳格subset・Python差分](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/PAYMENT_POLICY.md)。候補は 145,920 bytes、SHA256 `ea82c6468f339ed280005e1a270a511b1a8594452ef3de6fb546de43aa6ba454` です。両対応Rubyの全回帰・新規136項目、独立した日時/PISP検査で候補を確認しました。公開はOwnerの最終判断待ちです。
