# 未公開0.4.0診断候補 / Unreleased diagnostic candidate

通常のDockerfile・Gemfile・Gemfile.lockは公開済み0.3.0です。未公開Gemを通常起動の依存にしません。
The default demo remains on published 0.3.0. This explicit opt-in uses a normally installed local candidate, not a source load-path substitution.

本体の診断PRをチェックアウトし、固定依存・対応MRIの隔離環境で候補Gemをbuildしてください。
検証済みの同じ候補を、Git管理対象外のcandidate/ap2_mandate_verifier-0.4.0.gemに置きます。
候補は44032 bytes、SHA256 `b212db01e7deb18dcef1199414f9d93ef43cb1f74b62baa55306de3955dfe177` です。
Dockerfile.candidateがインストール前にsize・hashを検証します。候補lockのchecksumとも一致することを確認してください（変更した候補は再検証・lock更新が必要です）。

```sh
docker build -t ap2-diagnostics-demo:stable .
docker build -f Dockerfile.candidate -t ap2-diagnostics-demo:candidate .
docker run --rm --network none --tmpfs /demo/tmp --tmpfs /demo/log ap2-diagnostics-demo:stable bundle exec ruby test/demo_test.rb
docker run --rm --network none --tmpfs /demo/tmp --tmpfs /demo/log ap2-diagnostics-demo:candidate bundle exec ruby test/demo_test.rb
docker run --rm -p 127.0.0.1:3000:3000 ap2-diagnostics-demo:candidate
```

ローカル画面に公開前候補と表示されます。正常・改ざん・期限切れに加え、「注文の通貨を渡し忘れる」を
選ぶとrejected / invalid_host_contextのまま、input_assembly / order.currency / missing_required_fieldと
日本語の確認候補を取得できます。改ざん・期限切れは具体的な原因を断定せず確認候補を示します。
成功時は失敗診断なし、Evidenceは購入許可ではありません。通常0.3.0では診断欄と追加シナリオを出しません。

Select “注文の通貨を渡し忘れる” to inspect a missing-currency diagnostic. Existing tampered/expired examples display
safe check candidates. Core English/Japanese usage: [diagnostic guide](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/DIAGNOSTICS.md).

Gem公開、tag・Release、Web公開、実決済、外部Issuer通信、本番GOは行いません。
After a separately approved gem release, the ordinary dependency can be updated in a separate release-linked change.
