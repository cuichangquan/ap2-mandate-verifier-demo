# frozen_string_literal: true
require "minitest/autorun"
require_relative "../app/services/merchant_candidate"
class MerchantCandidateTest < Minitest::Test
  def test_signing_receipt_business_separation_and_wrong_signer
    result = MerchantCandidate.call
    assert_equal 43, result[:checkout_hash].length
    assert_equal 43, result[:reference].length
    refute_equal result[:checkout_hash], result[:reference]
    success, error = result[:rows]
    assert_equal "Success", success[:outcome]
    assert success[:verified]
    assert success[:purchase_succeeded]
    refute success[:purchase_rejected]
    assert_equal "Error", error[:outcome]
    assert error[:verified]
    refute error[:purchase_succeeded]
    assert error[:purchase_rejected]
    result[:rows].each { |row| refute row[:wrong_issuer_verified] }
  end
end
