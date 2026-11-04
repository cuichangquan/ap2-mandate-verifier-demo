# CheckoutとPaymentの選択的開示 — 1.3.0候補

公開前の候補Gemを使うローカルRuby単体デモです。通常Rails起動と公開版の例は1.2.0のままです。候補GemはOwner判断前に公開しません。

SDKの候補Gemを `candidate/ap2_mandate_verifier-1.3.0.gem` へ置き、候補の確認済みSHA256を指定します。通常デモimageを先に用意してください。ホストへのRuby導入は不要です。

```sh
docker build --network none -f Dockerfile.checkout-candidate \
  --build-arg CANDIDATE_SHA256=fb95cf669bc4cba1cc1360653bfd7ae8aec58404f13810f6d5a8fb205bc8841d \
  -t ap2-checkout-candidate:local .
docker run --rm --network none --cpus 1 --memory 512m --pids-limit 128 \
  ap2-checkout-candidate:local timeout 120 ruby examples/selective_checkout_candidate.rb
```

候補imageは通常RailsのBundler経路とは別に、versionを明示した候補Gemの同梱例を実行します。生成する鍵はメモリ内の合成鍵だけです。機密の完全Openから販売者・商品候補を絞り、全要件・数量を残したCheckout検証とReceipt確認、続けて選択的PaymentとReceipt確認まで実行します。非選択候補・完全wire・salt・秘密鍵は出力しません。保持／送信するdisclosure数とissuer JWT不変を表示します。

販売者集合と各明細の商品候補は独立した許可集合です。相関条件を表現したとは扱いません。相関が必要なら別Openに分割してください。候補数・位置・同issuer JWTのリンク可能性は隠しません。検証成功と最終購入許可、Receipt真正性と実決済の確定は別です。同意・鍵trust・失効・注文の最新状態・nonce原子消費・重複防止・実決済はアプリ責任です。

[SDK仕様・API・Python限界](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/SELECTIVE_CHECKOUT.md)。公式Python上位APIの完全対応や一般AP2適合は主張しません。候補は 137,728 bytes、SHA256 `fb95cf669bc4cba1cc1360653bfd7ae8aec58404f13810f6d5a8fb205bc8841d` です。正式公開前の候補であり、公開版の証明ではありません。
