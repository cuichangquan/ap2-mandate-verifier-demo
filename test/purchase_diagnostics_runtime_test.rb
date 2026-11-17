# frozen_string_literal: true
# Reuses only normal public-API fixture setup. Run with -n /test_diagnostics_/.
require_relative "purchase_runtime_test"

class PurchaseRuntimeTest
  def test_diagnostics_error_receipt_and_replay_are_not_success_or_permission
    skip "candidate API required" unless AP2MandateVerifier::Diagnostic.respond_to?(:payment_flow)
    id = approve("error")
    output = run_purchase(id)
    assert_equal "receipt_error", output.fetch("receipt_status")
    refute_equal "mock_success_verified", output.fetch("payment_status")
    entries = output.fetch("diagnostics")
    refute_empty entries
    assert entries.all? { |entry| D::Diagnostics.hint(entry, locale: :en) && D::Diagnostics.hint(entry, locale: :ja) }
    first_wire = @stores.fetch("buyer").read(id).fetch("wires")
    run_purchase(id)
    assert_equal 1, count(id)
    assert_equal first_wire, @stores.fetch("buyer").read(id).fetch("wires")
  end

  def test_diagnostics_unknown_state_has_real_catalog_diagnostic_and_no_repeat
    skip "candidate API required" unless AP2MandateVerifier::Diagnostic.respond_to?(:payment_flow)
    id = approve("timeout")
    output = run_purchase(id)
    assert_equal "unverified", output.fetch("receipt_status")
    refute_empty output.fetch("diagnostics")
    assert_equal 1, count(id)
    reopen
    recovered = @roles.fetch("authority").recover(id: id)
    assert_equal "receipt_success", recovered.fetch("receipt_status")
    assert_equal 1, count(id)
  end

  def test_diagnostics_receipt_reference_uses_the_same_authentic_receipt
    skip "candidate API required" unless AP2MandateVerifier::Diagnostic.respond_to?(:payment_flow)
    id = approve
    output = run_purchase(id)
    assert_equal "receipt_success", output.fetch("receipt_status")
    row = @stores.fetch("buyer").read(id)
    receipt = @stores.fetch("seller").processor(id).fetch("receipt_jwt")
    context = @roles.fetch("seller").receipt_context(@stores.fetch("seller").read(id))
    args = {receipt_jwt: receipt, closed_sd_jwt: row.fetch("wires").fetch("payment_closed"), context: context, now: @clock}
    assert D::Protocol.verify_receipt(**args).verified?
    refused = D::Protocol.verify_receipt(**args.merge(context: context.merge(expected_payment_id: "different-expected-id")))
    refute refused.verified?
    entry = D::Diagnostics.capture("receipt", refused)
    assert_equal "receipt_reference_mismatch", entry.fetch("reason")
    assert_equal [entry], D::Diagnostics.normalize([entry])
    assert_equal 1, count(id)
  end

  def test_diagnostics_payment_expectation_mismatch_uses_signed_normal_control
    skip "candidate API required" unless AP2MandateVerifier::Diagnostic.respond_to?(:payment_flow)
    id = approve
    row = @stores.fetch("seller").read(id)
    inputs = @roles.fetch("seller").verification(row, buyer_wires(id))
    control = AP2MandateVerifier::Payment.verify(**inputs)
    assert control.verified?
    refused = AP2MandateVerifier::Payment.verify(**inputs.merge(expected_audience: "different-expected-audience"))
    refute refused.verified?
    entry = D::Diagnostics.capture("payment", refused)
    refute_nil entry
    assert_equal [entry], D::Diagnostics.normalize([entry.merge("hint" => "DO_NOT_RENDER")])
    refute_includes D::Diagnostics.hint(entry), "DO_NOT_RENDER"
    assert_equal 0, count(id)
  end
end
