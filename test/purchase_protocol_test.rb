# frozen_string_literal: true
require "minitest/autorun"
require "minitest/mock"
require_relative "../purchase_demo/protocol"

class PurchaseProtocolTest < Minitest::Test
  P = PurchaseDemo::Protocol
  M = AP2MandateVerifier
  NOW = 1_800_000_000

  def setup
    @provider, @agent, @merchant = Array.new(3) { OpenSSL::PKey::EC.generate("prime256v1") }
    @public = {provider: @provider.public_to_pem, agent: @agent.public_to_pem, merchant: @merchant.public_to_pem}
    @approval = P.approval(approval_id: "consent-1", provider_key: @provider,
      agent_public_key_pem: @public.fetch(:agent), now: NOW)
    @order = P.order(order_id: "tea-1")
    @jwt = P.sign_order(order: @order, merchant_key: @merchant)
    @nonce = "server-generated-nonce"
  end

  def close(jwt = @jwt, nonce: @nonce, now: NOW)
    P.close(approval: @approval, checkout_jwt: jwt, agent_key: @agent,
      public_keys: @public, nonce: nonce, now: now)
  end

  def inputs(wires, now: NOW, nonce: @nonce)
    saved = P.prepare(approval: @approval, order: @order, checkout_jwt: @jwt,
      public_keys: @public, nonce: @nonce, now: NOW)
    P.verification_inputs(approval: @approval, order: @order, checkout_jwt: @jwt,
      wires: wires, saved_challenge: saved, public_keys: @public, nonce: nonce, now: now)
  end

  def assert_authentic_order(jwt, quantity:, total:)
    checked = M::CheckoutJWT.verify(jwt: jwt, trusted_public_key_pem: @public.fetch(:merchant),
      expected_merchant_id: P::MERCHANT.fetch("id"), profile_ref: P::PROFILE)
    assert checked.verified?
    assert_equal quantity, checked.checkout.fetch("line_items").first.fetch("quantity")
    assert_equal total, checked.checkout.fetch("totals").last.fetch("amount")
  end

  def test_approved_terms_and_complete_public_verification
    assert_equal 3, @approval.fetch("quantity")
    assert_equal 3000, @approval.fetch("max_total")
    assert @approval.frozen?
    assert @approval.fetch("checkout_open").frozen?
    assert_authentic_order(@jwt, quantity: 3, total: 2400)
    wires = close
    checked = M::Payment.verify(**inputs(wires))
    assert checked.verified?
    assert_equal 2400, checked.payment.fetch("payment_amount").fetch("amount")
    assert @approval.fetch("checkout_open") == wires.fetch("checkout_open"), "original Checkout Open changed"
    assert @approval.fetch("payment_open") == wires.fetch("payment_open"), "original Payment Open changed"
    assert @jwt == wires.fetch("checkout_jwt"), "original Checkout JWT changed"
    assert wires.fetch("payment_closed").end_with?("~")
  end

  def test_authentic_short_quantity_is_refused_at_checkout_issuance
    jwt = P.sign_order(order: P.order(order_id: "short", quantity: 2), merchant_key: @merchant)
    assert_authentic_order(jwt, quantity: 2, total: 1600)
    calls = 0
    signing = M::CheckoutJWT.es256_signer(private_key: @agent)
    error = P.stub(:signer, ->(_) { ->(input) { calls += 1; signing.call(input) } }) do
      assert_raises(P::Invalid) { close(jwt) }
    end
    assert_equal 0, calls
    assert_equal :checkout_refused, error.code
    assert_nil error.cause
    # This establishes signed-input issuance refusal, not a malicious complete
    # chain reaching merchant verification. No private SDK fixture is used.
  end

  def test_authentic_over_budget_is_refused_at_payment_issuance
    jwt = P.sign_order(order: P.order(order_id: "costly", unit_price: 1200), merchant_key: @merchant)
    assert_authentic_order(jwt, quantity: 3, total: 3600)
    calls = 0
    signing = M::CheckoutJWT.es256_signer(private_key: @agent)
    error = P.stub(:signer, ->(_) { ->(input) { calls += 1; signing.call(input) } }) do
      assert_raises(P::Invalid) { close(jwt) }
    end
    assert_equal 1, calls # Checkout signed; invalid Payment never signed.
    assert_equal :payment_refused, error.code
    assert_nil error.cause
  end

  def test_tampering_nonce_and_expiry_do_not_authorize
    assert_raises(P::Invalid) { close(@jwt + "x") }
    refute M::Payment.verify(**inputs(close(nonce: "wrong"))).verified?
  end

  def test_expired_authority_does_not_authorize
    wires = close
    begin
      raw = inputs(wires, now: NOW + 600)
    rescue M::InputBuilder::Invalid
      return # Independent expired trust failed closed before verification.
    end
    refute M::Payment.verify(**raw).verified?
  end

  def test_receipt_authenticity_outcome_and_first_wire_binding
    wires = close
    wire = wires.fetch("payment_closed")
    context = P.receipt_context(payment_id: "payment-1", merchant_public_key_pem: @public.fetch(:merchant),
      not_before: NOW, not_after: NOW + 900)
    %w[Success Error].each do |outcome|
      receipt = P.receipt(closed_sd_jwt: wire, payment_id: "payment-1", outcome: outcome,
        merchant_key: @merchant, now: NOW)
      result = P.verify_receipt(receipt_jwt: receipt, closed_sd_jwt: wire, context: context, now: NOW)
      assert result.verified?
      assert_equal outcome == "Success", result.payment_succeeded?
      assert_equal outcome == "Error", result.payment_rejected?
      replacement = close.fetch("payment_closed")
      refute wire == replacement, "re-signing must produce different original bytes"
      refute P.verify_receipt(receipt_jwt: receipt, closed_sd_jwt: replacement, context: context, now: NOW).verified?
      refute P.verify_receipt(receipt_jwt: receipt, closed_sd_jwt: wire,
        context: context.merge(expected_payment_id: "other"), now: NOW).verified?
    end
  end
end
