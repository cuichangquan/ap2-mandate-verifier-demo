# frozen_string_literal: true
module PurchaseDemo
  class Buyer < Role
    def transport = @transport ||= Transport.new(role: "buyer")
    def control(payload)
      id = id_from(payload)
      case payload.fetch("command")
      when "provision"
        approval, scenario = payload.values_at("approval", "scenario")
        raise BoundaryError unless SCENARIOS.include?(scenario) && approval.fetch("approval_id") == id && terms_valid?(approval)
        old = @store.save_once(id, {"id" => id, "approval" => approval, "scenario" => scenario})
        raise BoundaryError unless old.values_at("approval", "scenario") == [approval, scenario]
        {"provisioned" => true}
      when "run" then run(id)
      when "status" then status(id)
      when "recover" then recover(id)
      else raise BoundaryError
      end
    end
    def run(id)
      @store.lock(id) do
        row = record(id)
        return {"summary" => summary(row)} if row["refused"]
        unless row["wires"]
          offer = transport.a2a(command: "offer", payload: {"purchase_id" => id})
          order = offer.fetch("order")
          display = {"quantity" => order.fetch("line_items").sum { |line| line.fetch("quantity") },
            "amount" => order.fetch("totals").find { |t| t.fetch("type") == "total" }.fetch("amount"), "currency" => order.fetch("currency")}
          row = @store.update(id) { |r| r.merge("summary" => summary(r).merge("offer" => display)) }
          wires = Protocol.close(approval: row.fetch("approval"), checkout_jwt: offer.fetch("checkout_jwt"),
            agent_key: key, public_keys: keys, nonce: offer.fetch("nonce"), now: now)
          if row.fetch("scenario") == "tampered"
            wires = JSON.parse(JSON.generate(wires))
            pieces = wires.fetch("checkout_terminal").split(".")
            pieces[-1] = (pieces[-1][0] == "A" ? "B" : "A") + pieces[-1][1..]
            wires["checkout_terminal"] = pieces.join(".")
          end
          row = @store.update(id) { |r| r.merge("wires" => wires) }
        end
        # Persist the FIRST exact wire before sending. A lost response never
        # causes fresh issuance, a new approval, or a different processor key.
        consume(row, transport.a2a(command: "purchase", payload: {"purchase_id" => id, "wires" => row.fetch("wires")}))
      rescue Protocol::Invalid => error
        reason = error.code == :checkout_refused ? "Checkoutの署名・数量・承認条件・有効期限の確認に失敗し、発行を拒否しました。" :
          "Paymentの署名・予算・承認条件・有効期限の確認に失敗し、発行を拒否しました。"
        row = @store.update(id) { |r| r.merge("refused" => true, "summary" => summary(r).merge(
          "ap2_status" => "条件不一致・発行拒否", "app_status" => "拒否・未受理", "payment_status" => "未開始", "reason" => reason)) }
        {"summary" => summary(row)}
      rescue Transport::Error
        uncertain(id)
      end
    end
    def status(id)
      row = record(id)
      return {"summary" => summary(row)} unless row["wires"]
      consume(row, transport.a2a(command: "status", payload: {"purchase_id" => id}))
    rescue Transport::Error
      {"summary" => summary(record(id))}
    end
    def recover(id)
      row = record(id)
      return {"summary" => summary(row)} unless row["wires"]
      consume(row, transport.a2a(command: "recover", payload: {"purchase_id" => id}))
    rescue Transport::Error
      uncertain(id)
    end
    def consume(row, result)
      public_result = result.fetch("summary").slice("ap2_status", "app_status", "payment_status", "execution_count", "reason")
      next_summary = summary(row).merge(public_result)
      receipt = result["receipt_jwt"]
      if receipt
        approval = row.fetch("approval")
        context = Protocol.receipt_context(payment_id: row.fetch("id"), merchant_public_key_pem: keys.fetch(:merchant),
          not_before: approval.fetch("issued_at"), not_after: approval.fetch("issued_at") + 86_400)
        checked = Protocol.verify_receipt(receipt_jwt: receipt, closed_sd_jwt: row.fetch("wires").fetch("payment_closed"), context: context, now: now)
        next_summary["payment_status"] = if checked.verified?
          checked.payment_succeeded? ? "模擬成功（Receipt確認済み）" : "模擬失敗（Error確認済み）"
        else
          "成功未確認・再決済禁止"
        end
        next_summary["receipt_status"] = checked.verified? ? (checked.payment_succeeded? ? "真正なSuccess・購入成功通知" : "真正なError・購入成功ではない") : "拒否・この購入の真正なReceiptではない"
        next_summary["reason"] = if !checked.verified?
          "Receiptの署名または取引ID・元のPaymentとの結合が一致しません。購入成功として扱わず、再決済もしません。"
        elsif checked.payment_succeeded?
          "承認条件、AP2検証、永続受理、模擬決済、購入側のReceipt確認が完了しました。実際のお金は動いていません。"
        else
          "Error Receiptの署名は真正ですが、模擬決済は失敗です。同じ承認を再利用して決済しません。"
        end
      else
        next_summary["receipt_status"] = "未確認"
        next_summary["payment_status"] = "成功未確認・照会待ち" unless result["summary"]["payment_status"] == "未開始"
      end
      saved = @store.update(row.fetch("id")) { |r| r.merge("summary" => next_summary) }
      {"summary" => summary(saved)}
    end
    def uncertain(id)
      saved = @store.update(id) { |r| r.merge("summary" => summary(r).merge("payment_status" => "応答不明・照会待ち",
        "receipt_status" => "未確認", "reason" => "通信が時間切れになりました。同じ購入IDと原文を保持しています。状態を照会・復旧してください。")) }
      {"summary" => summary(saved)}
    end
  end
end
