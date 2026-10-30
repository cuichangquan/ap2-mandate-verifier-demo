require "ap2_mandate_verifier"
require "json"
require "digest"
require "base64"

class ScenarioVerifier
  LABELS = {"valid" => "正常な購入内容", "tampered" => "購入内容を改ざん", "expired" => "有効期限切れ"}.freeze
  FIXTURE = File.expand_path("../../fixtures/full.json", __dir__)
  SHA256 = "ac98f3b0c475365e2e7416cbb1838f1692a0ff2693c71dba0cb664c52b9ad42f"
  KEYS = %w[trust_json selection_json host_json root_presentation terminal_jws host_checkout_jws verified_at].freeze
  Outcome = Data.define(:title, :reason, :status, :code, :evidence_present, :time)

  def self.call(scenario)
    raise ArgumentError, "unknown scenario" unless LABELS.key?(scenario)
    raw = File.binread(FIXTURE)
    raise "fixture mismatch" unless Digest::SHA256.hexdigest(raw) == SHA256
    full = JSON.parse(raw) # Fresh detached input on every request.
    if scenario == "tampered"
      header, payload, signature = full.fetch("host_checkout_jws").split(".")
      checkout = JSON.parse(Base64.urlsafe_decode64(payload))
      checkout.fetch("line_items").first.fetch("item")["price"] = 999
      full["host_checkout_jws"] = [header, Base64.urlsafe_encode64(JSON.generate(checkout), padding: false), signature].join(".")
    elsif scenario == "expired"
      full["verified_at"] = 1_800_000_101 # Signed mandate exp=1800000100; trusted challenge remains in range.
    end
    inputs = KEYS.to_h { |key| [key.to_sym, full.fetch(key)] }
    result = AP2MandateVerifier.verify_checkout(**inputs)
    title = result.success? ? "検証成功" : (result.rejected? ? "拒否" : "検証不能")
    reason = case result.code
    when :scoped_research_verified then "合成データが固定profileの検査を通過しました。"
    when :host_binding_mismatch then "購入内容と保存済みHost情報が一致しません。"
    when :invalid_purchase_time, :invalid_host_validity, :challenge_time_mismatch
      "合成デモ時刻が有効期間の条件を満たしません。"
    else
      result.rejected? ? "固定profileの検査条件を満たしません。" : "検証を完了できません。購入処理は行いません。"
    end
    Outcome.new(title:, reason:, status: result.status, code: result.code,
      evidence_present: !result.evidence.nil?, time: full.fetch("verified_at"))
  rescue StandardError, LoadError
    Outcome.new(title: "検証不能", reason: "検証を完了できません。購入処理は行いません。",
      status: :unavailable, code: :demo_verification_unavailable, evidence_present: false, time: nil)
  end
end
