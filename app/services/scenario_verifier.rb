require "ap2_mandate_verifier"
require "json"
require "base64"

# Published 0.4.0 workflow: independent synthetic business data, never token trust.
class ScenarioVerifier
  LABELS = {"valid" => "正常な購入内容", "tampered" => "購入内容を改ざん", "expired" => "有効期限切れ", "missing_currency" => "注文の通貨を渡し忘れる"}.freeze
  Outcome = Data.define(:title, :reason, :status, :code, :evidence_present, :time, :diagnostic)
  DIRECTORY = File.expand_path("../../fixtures/input_builder", __dir__)

  def self.read(name)
    JSON.parse(File.binread(File.join(DIRECTORY, "#{name}.json")))
  end

  def self.trust(now)
    AP2MandateVerifier::InputBuilder.trust(snapshot: read("trust_snapshot"),
      tenant_id: "synthetic-tenant",
      issuer: {"identity" => "issuer", "purpose" => "checkout", "key_ref" => "issuer-1"},
      agent: {"identity" => "agent", "purpose" => "checkout", "key_ref" => "agent-1"},
      merchant: {"identity" => "shop", "purpose" => "checkout", "key_ref" => "merchant-1"},
      verified_at: now)
  end

  def self.call(scenario)
    raise ArgumentError, "unknown scenario" unless LABELS.key?(scenario)
    builder = AP2MandateVerifier::InputBuilder
    wires = read("signed_wires")
    issued = builder.prepare(trust: trust(1_800_000_000), order: read("order"),
      root_presentation: wires.fetch("root_presentation"),
      host_checkout_jws: wires.fetch("host_checkout_jws"),
      challenge_id: "synthetic-challenge", nonce: "n", issuer_id: "synthetic-host",
      not_before: 1_799_998_000, not_after: 1_800_002_000)
    # JSON bytes model a persisted, authenticated Host record. Never rebuild B
    # from current state during restore. A production Host owns actual storage.
    saved = issued.dup
    restored = builder.restore(saved_challenge: saved)
    now = scenario == "expired" ? 1_800_000_101 : 1_800_000_000
    current_order = read("order")
    current_order.delete("currency") if scenario == "missing_currency"
    if scenario == "tampered"
      header, payload, signature = wires.fetch("host_checkout_jws").split(".")
      checkout = JSON.parse(Base64.urlsafe_decode64(payload))
      checkout.fetch("line_items").first.fetch("item")["price"] = 999
      wires["host_checkout_jws"] = [header, Base64.urlsafe_encode64(JSON.generate(checkout), padding: false), signature].join(".")
    end
    result = builder.verify(trust: trust(now), saved_challenge: restored,
      order: current_order, **wires.transform_keys(&:to_sym),
      expected_challenge_issuer_id: "synthetic-host",
      clock_source_id: "fixed-synthetic-clock", verified_at: now)
    title = result.success? ? "検証成功" : (result.rejected? ? "拒否" : "検証不能")
    reason = case result.code
    when :scoped_research_verified then "業務情報から組み立てた入力が固定profileの検査を通過しました。"
    when :host_binding_mismatch then "購入内容と保存済みHost情報が一致しません。"
    when :invalid_purchase_time, :invalid_host_validity, :challenge_time_mismatch
      "合成デモ時刻が有効期間の条件を満たしません。"
    else
      result.rejected? ? "固定profileの検査条件を満たしません。" : "検証を完了できません。購入処理は行いません。"
    end
    diagnostic = result.diagnostic&.to_h(locale: :ja)
    Outcome.new(title:, reason:, status: result.status, code: result.code,
      evidence_present: !result.evidence.nil?, time: now, diagnostic: diagnostic)
  rescue StandardError, LoadError
    Outcome.new(title: "検証不能", reason: "検証を完了できません。購入処理は行いません。",
      status: :unavailable, code: :demo_verification_unavailable, evidence_present: false, time: nil, diagnostic: nil)
  end
end
