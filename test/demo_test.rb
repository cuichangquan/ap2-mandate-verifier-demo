ENV["RAILS_ENV"] = "test"
require "minitest/autorun"
require "minitest/mock"
require_relative "../config/application"
require "rack/mock"

class DemoTest < Minitest::Test
  def test_real_verifier_all_scenarios_and_repetition
    3.times do
      valid = ScenarioVerifier.call("valid")
      assert_equal :verified_research, valid.status
      assert_equal :scoped_research_verified, valid.code
      assert valid.evidence_present
      tampered = ScenarioVerifier.call("tampered")
      assert_equal :rejected, tampered.status
      assert_equal :host_binding_mismatch, tampered.code
      refute tampered.evidence_present
      expired = ScenarioVerifier.call("expired")
      assert_equal :rejected, expired.status
      assert_equal :invalid_purchase_time, expired.code
      refute expired.evidence_present
      assert_includes expired.reason, "有効期間"
    end
  end

  def test_candidate_diagnostics
    skip "unpublished candidate opt-in only" unless ScenarioVerifier::CANDIDATE
    missing = ScenarioVerifier.call("missing_currency")
    assert_equal :rejected, missing.status
    assert_equal :invalid_host_context, missing.code
    refute missing.evidence_present
    assert_equal "order.currency", missing.diagnostic[:field]
    assert_equal :missing_required_field, missing.diagnostic[:reason]
    assert_equal :input_assembly, missing.diagnostic[:stage]
    assert_includes missing.diagnostic[:hint], "必須項目"
    assert_nil ScenarioVerifier.call("valid").diagnostic
    assert_equal :host_binding, ScenarioVerifier.call("tampered").diagnostic[:stage]
    assert_equal :invalid_purchase_time, ScenarioVerifier.call("expired").diagnostic[:reason]
  end

  def test_errors_do_not_expose_exception_or_evidence
    File.stub(:binread, ->(*) { raise "sensitive fixture detail" }) do
      result = ScenarioVerifier.call("valid")
      assert_equal :unavailable, result.status
      refute result.evidence_present
      refute_includes result.reason, "sensitive"
    end
  end

  def test_page_and_real_post_with_csrf
    client = Rack::MockRequest.new(PurchaseDemo::Application)
    (ScenarioVerifier::CANDIDATE ? %w[valid tampered expired missing_currency valid] : %w[valid tampered expired valid]).each do |scenario|
      page = client.get("/", "HTTP_HOST" => "localhost")
      assert_equal 200, page.status
      assert_includes page.body, ScenarioVerifier::CANDIDATE ? "0.4.0" : "0.3.0"
      assert_includes page.body, "入力組み立て支援"
      refute_includes page.body, "公開前候補" unless ScenarioVerifier::CANDIDATE
      assert_includes page.body, "検証成功・Evidenceは購入許可ではありません。"
      assert_equal "same-origin", page.headers["referrer-policy"]
      token = page.body[/name="authenticity_token" value="([^"]+)"/, 1]
      refute_nil token
      cookie = Array(page.headers["set-cookie"]).map { |c| c.split(";", 2).first }.join("; ")
      result = client.post("/verify", "HTTP_HOST" => "localhost", "HTTP_COOKIE" => cookie,
        "HTTP_ORIGIN" => "http://localhost",
        params: {scenario: scenario, authenticity_token: token})
      assert_equal 200, result.status
      expected_code = {"valid" => "scoped_research_verified", "tampered" => "host_binding_mismatch", "expired" => "invalid_purchase_time", "missing_currency" => "invalid_host_context"}.fetch(scenario)
      assert_includes result.body, expected_code
      if scenario == "missing_currency"
        assert_includes result.body, "order.currency"
        assert_includes result.body, "missing_required_field"
        assert_includes result.body, "次の確認候補"
      end
      assert_includes result.body, scenario == "valid" ? "Evidence: あり（検証事実のみ）" : "Evidence: なし"
      assert_equal "no-store", result.headers["cache-control"]
      invalid = client.post("/verify", "HTTP_HOST" => "localhost", "HTTP_COOKIE" => cookie,
        params: {scenario: "https://untrusted.example/token", authenticity_token: token})
      assert_equal 400, invalid.status
      cross_origin = client.post("/verify", "HTTP_HOST" => "localhost", "HTTP_COOKIE" => cookie,
        "HTTP_ORIGIN" => "http://untrusted.example",
        params: {scenario: "valid", authenticity_token: token})
      assert_equal 422, cross_origin.status
    end
    assert_equal 403, client.get("/", "HTTP_HOST" => "untrusted.example").status
  end
end

class InputBuilderTest < Minitest::Test
  def test_returns_registered_failure_result
    result = AP2MandateVerifier::InputBuilder.verify(unknown: true)
    assert_equal :rejected, result.status
    assert_equal :invalid_host_context, result.code
    refute result.success?
    assert_nil result.evidence
    assert result.frozen?
  end

  def test_uses_business_inputs_without_legacy_full_fixture
    original = File.method(:binread)
    File.stub(:binread, ->(path, *args) {
      raise "legacy full fixture must not be used" if File.basename(path) == "full.json"
      original.call(path, *args)
    }) do
      assert_equal :scoped_research_verified, ScenarioVerifier.call("valid").code
      assert_equal :host_binding_mismatch, ScenarioVerifier.call("tampered").code
      assert_equal :invalid_purchase_time, ScenarioVerifier.call("expired").code
    end
  end
end
