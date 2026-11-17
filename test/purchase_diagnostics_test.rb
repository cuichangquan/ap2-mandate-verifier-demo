# frozen_string_literal: true
require "minitest/autorun"
require_relative "../purchase_demo/runtime"
require_relative "../purchase_demo/code_examples"

class PurchaseDiagnosticsTest < Minitest::Test
  D = PurchaseDemo::Diagnostics
  def test_absent_or_old_diagnostics_are_optional
    assert_equal [], D.normalize(nil)
    assert_equal [], D.normalize({})
    assert_nil D.capture("payment", Object.new)
    summary = PurchaseDemo::Runtime.safe_summary({"id" => "test", "scenario" => "valid", "summary" => {"reason" => "purchase_complete"}})
    assert_equal [], summary.fetch("diagnostics")
    assert_equal "purchase_complete", summary.fetch("reason")
  end

  def test_arbitrary_values_and_remote_hints_are_never_echoed
    entries = [{"operation" => "payment", "stage" => "private-stage", "field" => "nonce-secret", "reason" => "private-reason", "hint" => "private-hint"}]
    assert_equal [], D.normalize(entries)
    assert_nil D.hint(entries.first)
    assert_nil D.capture("untrusted-operation", Object.new)
  end

  def test_diagnostic_failure_does_not_change_source_result
    value = Object.new
    value.define_singleton_method(:diagnostic) { raise "private-exception-value" }
    assert_nil D.capture("payment", value)
  end

  def test_catalog_identity_cannot_be_relabelled_as_another_operation
    skip "candidate API required" unless AP2MandateVerifier::Diagnostic.respond_to?(:payment_flow)
    diagnostic = AP2MandateVerifier::Diagnostic.payment_flow(:payment_receipt_verification, :reported_error)
    result = Struct.new(:diagnostic).new(diagnostic)
    valid = D.capture("receipt", result)
    assert_equal [valid], D.normalize([valid])
    assert_equal [], D.normalize([valid.merge("operation" => "payment")])
    assert_equal [], D.normalize([valid.merge("field" => "private-field")])
  end

  def test_code_map_is_bounded_and_contains_no_dynamic_data
    assert_equal D::OPERATIONS.sort, PurchaseDemo::CodeExamples::EXAMPLES.keys.sort
    assert_includes PurchaseDemo::CodeExamples::EXAMPLES.fetch("start"), "start_with_diagnostic"
    assert_includes PurchaseDemo::CodeExamples::EXAMPLES.fetch("receipt"), "payment_succeeded?"
  end
end
