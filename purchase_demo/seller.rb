# frozen_string_literal: true
module PurchaseDemo
  class Seller < Role
    M = AP2MandateVerifier
    def provision(payload)
      id = id_from(payload)
      approval = payload.fetch("approval")
      scenario = payload.fetch("scenario")
      raise BoundaryError unless SCENARIOS.include?(scenario) && approval.fetch("approval_id") == id && terms_valid?(approval)
      @store.lock(id) do
        old = @store.read(id)
        if old
          raise BoundaryError unless old.values_at("approval", "scenario") == [approval, scenario]
          return {"provisioned" => true}
        end
        order = Protocol.order(order_id: "tea-#{id}", quantity: scenario == "quantity" ? 2 : 3,
          unit_price: scenario == "budget" ? 1200 : 800)
        checkout = Protocol.sign_order(order: order, merchant_key: key)
        nonce = SecureRandom.hex(24)
        saved = Protocol.prepare(approval: approval, order: order, checkout_jwt: checkout,
          public_keys: keys, nonce: nonce, now: now)
        @store.save_once(id, {"id" => id, "scenario" => scenario, "approval" => approval,
          "order" => order, "checkout_jwt" => checkout, "nonce" => nonce,
          "saved_challenge" => saved, "active" => true, "created_at" => now})
      end
      {"provisioned" => true}
    end

    def call(command, payload)
      id = id_from(payload)
      case command
      when "offer" then offer(record(id))
      when "purchase" then purchase(id, payload.fetch("wires"))
      when "status" then status(id)
      when "recover" then recover(id)
      else raise BoundaryError, "unknown command"
      end
    end

    def offer(row)
      raise BoundaryError unless row.fetch("active")
      {"purchase_id" => row.fetch("id"), "order" => row.fetch("order"),
        "checkout_jwt" => row.fetch("checkout_jwt"), "nonce" => row.fetch("nonce")}
    end

    def scope(row)
      id = row.fetch("id")
      {tenant_id: Protocol::TENANT, merchant_id: "tea-shop", operation_id: "purchase/#{id}",
        approval_id: id, occurrence_id: "one-purchase", order_id: row.fetch("order").fetch("id")}
    end
    def receipt_context(row)
      Protocol.receipt_context(payment_id: row.fetch("id"), merchant_public_key_pem: keys.fetch(:merchant),
        not_before: row.fetch("approval").fetch("issued_at"), not_after: row.fetch("approval").fetch("issued_at") + 86_400)
    end
    def verification(row, wires)
      Protocol.verification_inputs(approval: row.fetch("approval"), order: row.fetch("order"),
        checkout_jwt: row.fetch("checkout_jwt"), wires: wires, saved_challenge: row.fetch("saved_challenge"),
        public_keys: keys, nonce: row.fetch("nonce"), now: now)
    end
    def application_allows?(row)
      order = row.fetch("order")
      item = order.fetch("line_items").fetch(0)
      row.fetch("active") && terms_valid?(row.fetch("approval")) && now < row.fetch("approval").fetch("expires_at") &&
        order.fetch("status") == "ready_for_complete" && order.fetch("currency") == "JPY" &&
        item.fetch("item").fetch("id") == "tea" && item.fetch("quantity") == 3 &&
        order.fetch("totals").find { |t| t.fetch("type") == "total" }.fetch("amount") <= 3000
    end
    def with_acceptance
      ledger = M::PaymentAcceptance::SQLiteStore.new(path: File.join(Runtime.state_dir, "acceptance.sqlite3"))
      yield ledger, M::PaymentAcceptance::Service.new(store: ledger)
    ensure
      ledger&.close
    end
    def purchase(id, wires)
      row = record(id)
      with_acceptance do |ledger, service|
        # Previously consumed approval remains the SAME purchase even after proof
        # expiry. Lookup never grants a new Ticket or calls the processor.
        previous = service.lookup(**scope(row))
        return result(row, previous) if previous.processor_key
        inputs = verification(row, wires)
        checked = M::Payment.verify(**inputs)
        return reject(row, "拒否", "AP2が署名・承認条件・注文の結合を拒否しました。") unless checked.verified?
        return reject(row, "検証成功", "現在の承認・数量・予算・注文状態が実行条件を満たしません。") unless application_allows?(row)
        ledger.authorize!(**scope(row), mode: :conditional, profile_ref: M::Payment::PROFILE_REF,
          checkout: row.fetch("order"), payment: Protocol.payment_details(checkout_jwt: row.fetch("checkout_jwt"), public_keys: keys),
          receipt_context: receipt_context(row))
        accepted = service.accept(**scope(row), mode: :conditional, verification_inputs: inputs)
        return result(row, accepted) unless accepted.ticket
        # Independently read current protected state and clock immediately before
        # the SDK CAS. No mutation/revocation endpoint exists in this local demo.
        fresh = record(id)
        return reject(row, "検証成功", "承認の現在状態が変わったため開始しません。受理予約は保持します。", app_status: "実行拒否・受理予約保持") unless application_allows?(fresh)
        execution = service.start(ticket: accepted.ticket, verification_inputs: verification(fresh, wires))
        return result(row, service.lookup(**scope(row))) unless execution
        receipt = Protocol.receipt(closed_sd_jwt: execution.closed_sd_jwt, payment_id: id,
          merchant_key: key, now: now, outcome: row.fetch("scenario") == "error" ? "Error" : "Success")
        @store.process_once(id: id, processor_key: execution.processor_key,
          result: {"receipt_jwt" => receipt, "outcome" => row.fetch("scenario") == "error" ? "Error" : "Success"})
        if row.fetch("scenario") == "timeout"
          service.unknown(ticket: accepted.ticket)
          sleep 3 # Real response timeout AFTER durable mock side effect.
          return result(row, service.lookup(**scope(row)))
        end
        final = service.finish(ticket: accepted.ticket, receipt_jwt: receipt, verified_at: now)
        result(row, final)
      end
    rescue ArgumentError, KeyError, M::PaymentAcceptance::Conflict
      reject(row, "拒否", "署名・原文・注文との結合が一致しません。")
    end

    def status(id)
      row = record(id)
      with_acceptance { |_ledger, service| result(row, service.lookup(**scope(row))) }
    end
    def recover(id)
      row = record(id)
      with_acceptance do |_ledger, service|
        old = service.lookup(**scope(row))
        processor = @store.processor(id)
        if processor && %i[pending unknown].include?(old.status)
          old = service.reconcile(**scope(row), receipt_jwt: processor.fetch("receipt_jwt"), verified_at: now)
        end
        result(row, old)
      end
    end
    def reject(row, ap2, reason, app_status: "拒否・未受理")
      rejected = summary(row).merge("ap2_status" => ap2, "app_status" => app_status,
        "payment_status" => "未開始", "execution_count" => 0, "reason" => reason)
      @store.update(row.fetch("id")) { |r| r.merge("summary" => rejected) }
      {"summary" => rejected}
    end
    def result(row, accepted)
      processor = @store.processor(row.fetch("id"))
      state = accepted.status.to_s
      if !accepted.processor_key && !processor && state == "rejected" && row["summary"]
        return {"summary" => summary(row), "acceptance_state" => "not_accepted"}
      end
      finished = %w[receipt_success receipt_error].include?(state)
      started = accepted.processor_key || processor
      uncertain = %w[unavailable conflict].include?(state)
      output = {"summary" => summary(row).merge("ap2_status" => started ? "検証成功" : (uncertain ? "状態不明" : "未実行"),
        "app_status" => started ? "永続受理済み・再実行不可" : (uncertain ? "状態照会が必要・再実行禁止" : "承認済み・未受理"),
        "payment_status" => finished ? (state == "receipt_success" ? "模擬成功" : "模擬失敗") : (started || uncertain ? "応答不明・照会待ち" : "未開始"),
        "execution_count" => processor ? processor.fetch("execution_count") : 0,
        "reason" => finished ? "保存された模擬決済結果を返しました。購入側のReceipt確認が必要です。" : "同じ購入IDの状態を保持しています。新しい支払い許可は発行しません。"),
        "acceptance_state" => state}
      if accepted.receipt_jwt
        receipt = accepted.receipt_jwt
        # Isolated, opt-in synthetic delivery faults. The authoritative ledger
        # always retains the genuine original Receipt.
        if row.fetch("scenario") == "wrong_receipt"
          receipt = Protocol.receipt(closed_sd_jwt: accepted.closed_sd_jwt, payment_id: "another-purchase",
            merchant_key: key, now: now)
        elsif row.fetch("scenario") == "invalid_receipt"
          pieces = receipt.split(".")
          pieces[-1] = (pieces[-1][0] == "A" ? "B" : "A") + pieces[-1][1..]
          receipt = pieces.join(".")
        end
        output["receipt_jwt"] = receipt
      end
      output
    end
  end
end
