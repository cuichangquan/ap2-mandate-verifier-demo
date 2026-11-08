# frozen_string_literal: true
module PurchaseDemo
  # Compatibility is exact and read-only. Never translate or rewrite signed
  # approval/offer/Receipt originals, and never use translated text for a decision.
  module SummaryCodes
    STATUS_FIELDS = %w[ap2_status app_status payment_status receipt_status].freeze
    STATUS_CODES = ["not_run", "approved", "approved_pending", "not_started", "unverified", "issuance_refused", "rejected", "not_accepted", "verified", "unknown", "accepted_no_retry", "lookup_required", "reservation_held", "mock_success", "mock_error", "mock_success_verified", "mock_error_verified", "unconfirmed_no_retry", "unconfirmed_pending", "response_unknown", "receipt_success", "receipt_error", "receipt_rejected"].freeze
    REASON_CODES = ["approval_saved", "authority_unreachable", "checkout_refused", "payment_refused", "receipt_rejected", "purchase_complete", "payment_failed", "response_timeout", "ap2_rejected", "application_rejected", "approval_changed", "binding_mismatch", "result_saved", "purchase_retained"].freeze
    LEGACY_STATUSES = {
      "未実行" => "not_run",
      "明示承認済み" => "approved",
      "承認済み・未受理" => "approved_pending",
      "未開始" => "not_started",
      "未確認" => "unverified",
      "条件不一致・発行拒否" => "issuance_refused",
      "拒否" => "rejected",
      "拒否・未受理" => "not_accepted",
      "検証成功" => "verified",
      "状態不明" => "unknown",
      "永続受理済み・再実行不可" => "accepted_no_retry",
      "状態照会が必要・再実行禁止" => "lookup_required",
      "実行拒否・受理予約保持" => "reservation_held",
      "模擬成功" => "mock_success",
      "模擬失敗" => "mock_error",
      "模擬成功（Receipt確認済み）" => "mock_success_verified",
      "模擬失敗（Error確認済み）" => "mock_error_verified",
      "成功未確認・再決済禁止" => "unconfirmed_no_retry",
      "成功未確認・照会待ち" => "unconfirmed_pending",
      "応答不明・照会待ち" => "response_unknown",
      "真正なSuccess・購入成功通知" => "receipt_success",
      "真正なError・購入成功ではない" => "receipt_error",
      "拒否・この購入の真正なReceiptではない" => "receipt_rejected",
      "承認済み" => "approved",
      "未実施" => "not_run"
    }.freeze
    LEGACY_REASONS = {
      "承認を保存しました。購入Agentを実行してください。" => "approval_saved",
      "応答を確認できません。同じ購入IDの状態を照会してください。新しい購入許可は発行しません。" => "authority_unreachable",
      "Checkoutの署名・数量・承認条件・有効期限の確認に失敗し、発行を拒否しました。" => "checkout_refused",
      "Paymentの署名・予算・承認条件・有効期限の確認に失敗し、発行を拒否しました。" => "payment_refused",
      "Receiptの署名または取引ID・元のPaymentとの結合が一致しません。購入成功として扱わず、再決済もしません。" => "receipt_rejected",
      "承認条件、AP2検証、永続受理、模擬決済、購入側のReceipt確認が完了しました。実際のお金は動いていません。" => "purchase_complete",
      "Error Receiptの署名は真正ですが、模擬決済は失敗です。同じ承認を再利用して決済しません。" => "payment_failed",
      "通信が時間切れになりました。同じ購入IDと原文を保持しています。状態を照会・復旧してください。" => "response_timeout",
      "AP2が署名・承認条件・注文の結合を拒否しました。" => "ap2_rejected",
      "現在の承認・数量・予算・注文状態が実行条件を満たしません。" => "application_rejected",
      "承認の現在状態が変わったため開始しません。受理予約は保持します。" => "approval_changed",
      "署名・原文・注文との結合が一致しません。" => "binding_mismatch",
      "保存された模擬決済結果を返しました。購入側のReceipt確認が必要です。" => "result_saved",
      "同じ購入IDの状態を保持しています。新しい支払い許可は発行しません。" => "purchase_retained"
    }.freeze

    module_function
    def status(value)
      return value if STATUS_CODES.include?(value)
      LEGACY_STATUSES[value]
    end

    def reason(value)
      return value if REASON_CODES.include?(value)
      LEGACY_REASONS[value]
    end

    def normalize(summary)
      summary.each_with_object({}) do |(key, value), result|
        result[key] = if STATUS_FIELDS.include?(key)
          status(value) || value
        elsif key == "reason"
          reason(value) || value
        else
          value
        end
      end
    end
  end
end
