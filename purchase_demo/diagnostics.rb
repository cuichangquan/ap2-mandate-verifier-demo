# frozen_string_literal: true
module PurchaseDemo
  # Only catalog identities cross the role/storage boundary. Never carry hints,
  # arbitrary exception text, or payment values from a remote result into the UI.
  module Diagnostics
    OPERATIONS = %w[payment accept start lookup finish reconcile receipt].freeze
    STAGES = {"payment" => "payment_verification", "receipt" => "payment_receipt_verification",
      "start" => "payment_execution"}.freeze
    module_function

    def capture(operation, result)
      return nil unless OPERATIONS.include?(operation) && result.respond_to?(:diagnostic)
      diagnostic = result.diagnostic
      return nil unless diagnostic
      {"operation" => operation, "stage" => diagnostic.stage.to_s,
        "field" => diagnostic.field&.to_s, "reason" => diagnostic.reason.to_s}
    rescue StandardError, LoadError
      nil # Supplemental display failure must not change an execution decision.
    end

    def normalize(entries)
      return [] unless entries.instance_of?(Array)
      entries.first(12).filter_map { |entry| canonical(entry) }.uniq
    end

    def canonical(entry)
      return nil unless entry.instance_of?(Hash) && OPERATIONS.include?(entry["operation"])
      diagnostic = resolve(entry)
      return nil unless diagnostic && diagnostic.stage.to_s == entry["stage"] &&
        diagnostic.field&.to_s == entry["field"] && diagnostic.reason.to_s == entry["reason"]
      {"operation" => entry["operation"], "stage" => diagnostic.stage.to_s,
        "field" => diagnostic.field&.to_s, "reason" => diagnostic.reason.to_s}
    rescue StandardError, LoadError
      nil
    end

    def resolve(entry)
      return nil unless entry["reason"].instance_of?(String) && entry["reason"].bytesize <= 100
      stage = STAGES.fetch(entry["operation"], "payment_acceptance")
      return nil unless entry["stage"] == stage
      klass = AP2MandateVerifier::Diagnostic
      return nil unless klass.respond_to?(:payment_flow)
      klass.payment_flow(stage.to_sym, entry["reason"].to_sym)
    end

    def hint(entry, locale: :en)
      safe = canonical(entry)
      safe && resolve(safe).hint(locale: locale)
    end

    def append(entries, operation, result)
      normalize(Array(entries) + [capture(operation, result)].compact)
    end
  end
end
