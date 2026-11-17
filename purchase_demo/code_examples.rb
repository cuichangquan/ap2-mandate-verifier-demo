# frozen_string_literal: true
module PurchaseDemo
  # Abbreviations of the actual calls in seller.rb / buyer.rb / protocol.rb.
  # This is inert text, not eval-able input or a payment action endpoint.
  module CodeExamples
    EXAMPLES = {
      "payment" => "checked = AP2MandateVerifier::Payment.verify(**inputs)\nchecked.verified? # existing decision\nchecked.diagnostic # supplemental, may be nil",
      "accept" => "accepted = service.accept(**scope(row), mode: :conditional,\n  verification_inputs: inputs)\naccepted.ticket # existing execution capability\naccepted.diagnostic # not a capability",
      "start" => "started = service.start_with_diagnostic(\n  ticket: accepted.ticket, verification_inputs: verification(fresh, wires))\nexecution = started.execution\nstarted.diagnostic # nil execution never means safe to retry",
      "lookup" => "accepted = service.lookup(**scope(row))\naccepted.status\naccepted.diagnostic # lookup never calls the processor",
      "finish" => "final = service.finish(ticket: accepted.ticket,\n  receipt_jwt: receipt, verified_at: now)\nfinal.status\nfinal.diagnostic",
      "reconcile" => "saved = service.reconcile(**scope(row),\n  receipt_jwt: processor.fetch(\"receipt_jwt\"), verified_at: now)\nsaved.diagnostic # no second payment",
      "receipt" => "checked = AP2MandateVerifier::PaymentReceipt.verify(\n  jwt: receipt, closed_sd_jwt: row.fetch(\"wires\").fetch(\"payment_closed\"),\n  **context, verified_at: now)\nchecked.verified? # authenticity and references\nchecked.payment_succeeded? # separate reported outcome\nchecked.diagnostic"
    }.transform_values(&:freeze).freeze
  end
end
