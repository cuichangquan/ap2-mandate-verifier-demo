# Payment候補の選択的開示 — 未公開1.2.0候補

通常のRailsデモは公開済み1.1.0を維持します。新しい候補は明示的な`SelectivePayment` profileで、支払先のみ・決済手段のみ・双方の候補を個別開示できます。旧`Payment`は全内容profileのままであり、新しいOpenを黙って受理しません。Checkout側の開示機能は変更しません。

候補のRuby単体例は、非選択候補の値／開示を保持する機密のfull issuanceと、相手へ送る縮小presentationを区別します。実出力では候補数・開示数・bytes、issuer JWTが同じで提示bytesが変わったことを表示し、選択Payment→完全Checkout結合→成功／エラーReceiptまで確認します。full wire、非選択値、salt、秘密鍵は出力しません。候補数・commitment位置・同じissuer JWTによるリンク可能性は隠れません。

公式の独立allowlistは直積です。保護された承認記録の`approved_combinations`が候補全直積と一致しない相関subsetは署名前に拒否します。相関が必要な場合は、許可されたsingleton組合せまたは承認済み矩形subsetごとに別Openを発行し、金額／期限／Checkout参照を維持してください。相関リストを勝手に直積へ拡張しません。

## 候補専用Docker

RubyGemsから1.2.0を取得しないでください。Owner向けに用意された候補Gemをignoredな`candidate/ap2_mandate_verifier-1.2.0.gem`へ置き、[Issue#238の最終manifest](https://github.com/cuichangquan/ap2-mandate-verifier/issues/238)に記録された正確なSHA256を使用します。公開1.1.0の通常デモをbaseとして、同じ候補bytesを`--local`導入します。SDK sourceや認証ファイルはbuild contextへ含めません。

```sh
docker build --platform linux/arm64 -t ap2-mandate-verifier-demo:local .
docker build --platform linux/arm64 -f Dockerfile.selective-candidate \
  --build-arg CANDIDATE_SHA256=FINAL_CANDIDATE_SHA256 \
  -t ap2-selective-payment120-demo:candidate .
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-selective-payment120-demo:candidate timeout 120 ruby examples/selective_payment_candidate.rb
```

別途候補を導入した環境なら`ruby examples/selective_payment_candidate.rb`でも実行できます。通常Bundler lockは1.1.0なので、この候補専用entryを`bundle exec`で起動しません。候補の追加導入後も通常Railsは固定lockの1.1.0を使います。

[仕様・API・必須条件・Python制約](https://github.com/cuichangquan/ap2-mandate-verifier/blob/payment-selective-120/docs/SELECTIVE_PAYMENT.md)。Python上位selectorは候補array leafの選択を直接扱えず、相互運用は公式低水準SDKと明示profile adapter・独立期待値を用います。上位facade全対応や一般AP2互換とは主張しません。

全データ・鍵・Receipt結果は模擬です。SDK検証は実行許可ではなく、Receipt真正性と報告結果は別です。本人認証・同意・鍵trust、永続的重複防止と原子的状態更新、実決済、未知結果の照合はアプリ責任です。候補は未公開で、tag/Release/RubyGems公開・Webデプロイは実施しません。
