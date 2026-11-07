# frozen_string_literal: true
# Run INSIDE the authority container after Compose starts all three processes.
# This file prints only synthetic IDs, stage summaries and assertion counts.
require "bundler/setup"
require "minitest/autorun"
require "securerandom"
require_relative "../purchase_demo/runtime"

class PurchaseIntegrationTest < Minitest::Test
  def setup
    @authority = PurchaseDemo::Runtime.authority
  end
  def purchase(scenario)
    id = SecureRandom.uuid
    @authority.approve(id: id, scenario: scenario)
    @authority.run(id: id)
    [id, @authority.status(id: id)]
  end
  def assert_no_sensitive_output(value)
    text = JSON.generate(value)
    refute text.match?(/BEGIN .*PRIVATE KEY|checkout_open|payment_closed|nonce|eyJ[a-zA-Z0-9_-]{30}/), "public summary contains sensitive wire material"
  end
  def test_normal_and_repeated_purchase
    id, result = purchase("valid")
    assert_equal 1, result.fetch("execution_count")
    assert_includes result.fetch("receipt_status"), "真正なSuccess"
    assert_equal({"quantity" => 3, "amount" => 2400, "currency" => "JPY"}, result.fetch("offer"))
    3.times do
      repeated = @authority.run(id: id)
      assert_equal 1, repeated.fetch("execution_count")
      assert_equal result.fetch("receipt_status"), repeated.fetch("receipt_status")
      assert_no_sensitive_output(repeated)
    end
  end
  def test_authentic_offer_constraint_rejections
    {"budget" => [3, 3600], "quantity" => [2, 1600]}.each do |scenario, (quantity, amount)|
      id, result = purchase(scenario)
      assert_equal 0, result.fetch("execution_count")
      assert_equal "未開始", result.fetch("payment_status")
      assert_equal "条件不一致・発行拒否", result.fetch("ap2_status")
      assert_equal quantity, result.fetch("offer").fetch("quantity")
      assert_equal amount, result.fetch("offer").fetch("amount")
      assert_equal 0, @authority.run(id: id).fetch("execution_count")
      assert_no_sensitive_output(result)
    end
  end
  def test_tampering_never_starts_mock
    _id, result = purchase("tampered")
    assert_equal 0, result.fetch("execution_count")
    assert_equal "拒否", result.fetch("ap2_status")
    refute_includes result.fetch("receipt_status"), "購入成功通知"
  end
  def test_error_and_invalid_receipts_are_not_purchase_success
    %w[error wrong_receipt invalid_receipt].each do |scenario|
      _id, result = purchase(scenario)
      assert_equal 1, result.fetch("execution_count")
      refute_includes result.fetch("receipt_status"), "購入成功通知"
      assert_includes result.fetch("receipt_status"), scenario == "error" ? "真正なError" : "拒否"
      assert_no_sensitive_output(result)
    end
  end
  def test_real_timeout_then_query_recovery
    id, result = purchase("timeout")
    assert_equal 1, result.fetch("execution_count")
    assert_equal "未確認", result.fetch("receipt_status")
    recovered = @authority.recover(id: id)
    assert_equal 1, recovered.fetch("execution_count")
    assert_includes recovered.fetch("receipt_status"), "真正なSuccess"
    assert_equal 1, @authority.run(id: id).fetch("execution_count")
  end
end
