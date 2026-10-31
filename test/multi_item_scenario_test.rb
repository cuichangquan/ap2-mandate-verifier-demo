# frozen_string_literal: true
ENV["RAILS_ENV"] = "test"
require "minitest/autorun"
require_relative "../config/application"
require "rack/mock"

class MultiItemScenarioTest < Minitest::Test
  def test_full_builder_signature_evidence_and_receipts
    result = MultiItemScenario.call
    assert_equal [2, 3], result[:lines].map { |line| line["quantity"] }
    assert_equal 480, result[:amount]
    assert_equal :verified_research, result[:status]
    assert_equal :scoped_research_verified, result[:code]
    assert result[:evidence_present]
    assert_equal ["Success", "Error"], result[:rows].map { |row| row[:outcome] }
    assert result[:rows].all? { |row| row[:verified] }
    assert result[:rows][0][:purchase_succeeded]
    refute result[:rows][0][:purchase_rejected]
    refute result[:rows][1][:purchase_succeeded]
    assert result[:rows][1][:purchase_rejected]
  end

  def test_second_requirement_is_not_skipped
    result = MultiItemScenario.call(short_second: true)
    assert_equal [2, 2], result[:lines].map { |line| line["quantity"] }
    assert_equal :rejected, result[:status]
    assert_equal :constraint_mismatch, result[:code]
    refute result[:evidence_present]
    assert_empty result[:rows]
  end

  def test_candidate_page_uses_real_verifier_and_no_store
    response = Rack::MockRequest.new(PurchaseDemo::Application).get("/multi-item", "HTTP_HOST" => "localhost")
    assert_equal 200, response.status
    assert_equal "no-store", response.headers["cache-control"]
    %w[multi-item-scenario scoped_research_verified constraint_mismatch Success Error].each { |text| assert_includes response.body, text }
    assert_includes response.body, "購入成功通知 false"
  end
end
