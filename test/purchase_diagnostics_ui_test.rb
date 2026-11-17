# frozen_string_literal: true
require_relative "purchase_locale_test"

class PurchaseLocaleTest
  def test_diagnostics_code_panels_and_language_switch_are_read_only
    id, page = approved_page
    calls = @service.calls.dup
    @service.status_calls.clear
    %w[en ja].each do |locale|
      page = @browser.get("/purchases/#{id}?locale=#{locale}")
      assert_includes page.body, translated("diagnostics.title", locale)
      assert_includes page.body, translated("diagnostics.empty", locale)
      assert_includes page.body, "start_with_diagnostic"
      assert_includes page.body, "payment_succeeded?"
      refute_match(/translation missing/i, page.body)
    end
    assert_equal calls, @service.calls
    assert_empty @service.status_calls
  end

  def test_diagnostics_catalog_hints_are_localized_not_remote_text
    skip "candidate API required" unless AP2MandateVerifier::Diagnostic.respond_to?(:payment_flow)
    id, = approved_page
    diagnostic = AP2MandateVerifier::Diagnostic.payment_flow(:payment_receipt_verification, :reported_error)
    entry = PurchaseDemo::Diagnostics.capture("receipt", Struct.new(:diagnostic).new(diagnostic))
    @service.records.fetch(id)["diagnostics"] = [entry.merge("hint" => "REMOTE_SECRET_HINT")]
    %w[en ja].each do |locale|
      page = @browser.get("/purchases/#{id}?locale=#{locale}")
      assert_includes page.body, CGI.escapeHTML(diagnostic.hint(locale: locale.to_sym))
      assert_includes page.body, "reported_error"
      refute_includes page.body, "REMOTE_SECRET_HINT"
    end
  end

  def test_diagnostics_arbitrary_saved_fields_are_not_rendered
    id, = approved_page
    @service.records.fetch(id)["diagnostics"] = [{"operation" => "receipt", "stage" => "secret-stage", "field" => "secret-field", "reason" => "secret-reason", "hint" => "secret-hint"}]
    page = @browser.get("/purchases/#{id}")
    %w[secret-stage secret-field secret-reason secret-hint].each { |secret| refute_includes page.body, secret }
  end
end
