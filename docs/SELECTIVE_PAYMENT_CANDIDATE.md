# Payment候補の選択的開示 — 公開済み1.2.0

通常Railsデモは公式公開1.2.0を使用します。旧`Payment`の完全内容profileを維持し、新しい`SelectivePayment`を明示的に選びます。支払先のみ・決済手段のみ・双方の候補を個別開示できます。Checkout側の開示機能は変更しません。

```sh
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-mandate-verifier-demo:local timeout 120 bundle exec ruby examples/selective_payment.rb
```

公開Gemに同梱されたRuby単体例は、機密のfull issuance5disclosuresと相手へ送る縮小presentation3disclosuresを区別し、issuerJWT不変・提示bytes変更、完全Checkout結合、選択Payment、成功／エラーReceiptまで検証します。full wire、非選択値、salt、秘密鍵は出力しません。候補数・commitment位置・同issuerJWTによるリンク可能性は隠れません。非selective軸は明示的に全候補が可視です。

独立allowlistは直積です。保護された承認記録のapproved_combinationsが全直積と一致しない相関subsetは署名前に拒否します。相関が必要な場合は、許可されたsingletonまたは承認済み矩形subsetごとに別Openを発行し、金額／期限／Checkout参照を維持します。候補の配列を勝手に組み合わせて承認を広げません。

[公開実物・検証](PUBLISHED_120.md)、[SDK仕様・API・必須条件・Python限界](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/SELECTIVE_PAYMENT.md)。Python上位selectorはこの候補array選択を直接扱えず、相互運用は公式低水準SDK＋明示profileadapterと独立期待値の範囲です。上位facade全対応や一般AP2適合とは主張しません。

旧examples/selective_payment_candidate.rbは公開Gemを選ぶ互換entryです。この文書名も既存リンクのため保持します。Dockerfile.selective-candidateは歴史的なローカルarchive比較経路だけで、通常利用や公式配布bytesの証明に使いません。

全データ・鍵・Receipt結果は模擬です。検証は実行許可ではなく、Receipt真正性と報告結果は別です。同意・鍵trust・永続的重複防止・原子的状態更新・実決済・未知結果の照合はアプリ責任です。Webデプロイや実決済は行いません。
