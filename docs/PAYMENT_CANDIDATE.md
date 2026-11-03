# Payment 1.1.0 — published example

The normal Rails demo now selects published 1.1.0. The Payment lifecycle remains a plain Ruby example, not a deployed payment service or live PSP integration. Run `bundle exec ruby examples/payment.rb` inside the demo Docker image; the older `examples/payment_candidate.rb` entry is retained for compatibility. Both load the SDK’s packaged Direct/conditional Checkout → Payment → Success/Error Payment Receipt sample with synthetic keys and results.

[Published artifact and validation](PUBLISHED_110.md), [SDK API and trust boundary](https://github.com/cuichangquan/ap2-mandate-verifier/blob/main/docs/PAYMENT.md), [GitHub Release](https://github.com/cuichangquan/ap2-mandate-verifier/releases/tag/v1.1.0). Rails is optional for SDK adoption.

検証成功は決済の実行許可ではありません。Receipt署名の検証成功とReceiptの成功／エラー結果は別です。単発利用の保証には利用アプリ側の永続的・原子的な状態管理が必要です。Receipt未着・検証不能・処理結果不明はpendingとして照合し、自動再試行しません。

This file retains its pre-publication filename to preserve links; its current instructions use the verified public distribution. No deployment or actual payment is performed.
