# Payment 1.1.0 candidate (unpublished)

The default Rails demo continues to install published 1.0.0. Payment is an optional plain Ruby candidate example, not a deployed checkout/payment service. No live PSP or network is used. The candidate must be installed from the exact Owner-reviewed Gem; `gem install -v 1.1.0` from RubyGems is not yet a valid setup instruction.

After installing the locally supplied candidate and its pinned dependencies in an isolated Docker environment, run `ruby examples/payment_candidate.rb`. This loads the SDK's packaged sample and exercises Direct and conditional Checkout → Payment → signed Success/Error Payment Receipt with synthetic keys/data. It does not use Bundler's default 1.0.0 lock, Rails, a database or a web server. Keep default Rails dependencies/startup unchanged until publication and a separately reviewed upgrade.

検証成功は決済の実行許可ではありません。Receipt署名の検証成功とReceiptの成功／エラー結果は別です。単発利用の保証には利用アプリ側の永続的・原子的な状態管理が必要です。Receipt未着・検証不能・処理結果不明はpendingとして照合し、自動再試行しません。

See [SDK Payment contract](https://github.com/cuichangquan/ap2-mandate-verifier/blob/payment-mandate-110/docs/PAYMENT.md), [work order / evidence](https://github.com/cuichangquan/ap2-mandate-verifier/issues/235). Candidate version/source/artifact and publication require the Owner's final judgment. This change performs no deployment or publication.
