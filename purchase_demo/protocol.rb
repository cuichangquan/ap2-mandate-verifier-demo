# frozen_string_literal: true

require "ap2_mandate_verifier"
require "openssl"

module PurchaseDemo
  # Cryptographic plumbing only. Callers own authenticated consent, protected
  # order/challenge records and durable acceptance. No key is loaded here.
  module Protocol
    M = AP2MandateVerifier
    PROFILE = M::ConditionalCheckout::PROFILE_REF
    TENANT = "tea-demo"
    MERCHANT = {"id" => "tea-shop", "name" => "Tea Shop"}.freeze
    INSTRUMENT = {"id" => "mock-card", "type" => "card"}.freeze
    AUDIENCE = "tea-merchant"
    RECEIPT_ISSUER = "tea-mock-processor"
    class Invalid < ArgumentError
      attr_reader :code
      def initialize(code)
        @code = code
        super("purchase presentation refused")
      end
    end
    module_function

    def signer(key) = M::CheckoutJWT.es256_signer(private_key: key)
    def totals(amount) = %w[subtotal total].map { |type| {"type" => type, "amount" => amount} }

    def immutable(value)
      case value
      when Hash then value.to_h { |k, v| [k.dup.freeze, immutable(v)] }.freeze
      when Array then value.map { |v| immutable(v) }.freeze
      when String then value.dup.freeze
      else value.freeze
      end
    end

    # Invoke only AFTER the authority has recorded explicit buyer consent.
    # Both Opens precede the seller offer; no exact offer is pre-approved here.
    def approval(approval_id:, provider_key:, agent_public_key_pem:, now:)
      raise ArgumentError, "approval id required" unless approval_id.is_a?(String) && !approval_id.empty?
      opening = M::ConditionalCheckout.issue_open(merchant: MERCHANT,
        requirements: [{"id" => "tea", "quantity" => 3,
          "acceptable_items" => [{"id" => "tea", "title" => "Tea"}]}],
        agent_public_key_pem: agent_public_key_pem, issued_at: now, expires_at: now + 600,
        signer: signer(provider_key), public_key_pem: provider_key.public_to_pem)
      payment_open = M::Payment.issue_open(open_checkout_sd_jwt: opening.root_presentation,
        constraints: [{"type" => "payment.amount_range", "currency" => "JPY", "max" => 3000},
          {"type" => "payment.allowed_payees", "allowed" => [MERCHANT]},
          {"type" => "payment.allowed_payment_instruments", "allowed" => [INSTRUMENT]}],
        fixed: {"payment_instrument" => INSTRUMENT}, agent_public_key_pem: agent_public_key_pem,
        issued_at: now, expires_at: now + 600, signer: signer(provider_key), public_key_pem: provider_key.public_to_pem)
      immutable({"approval_id" => approval_id, "checkout_open" => opening.root_presentation,
        "payment_open" => payment_open, "quantity" => 3, "max_total" => 3000,
        "currency" => "JPY", "merchant_id" => MERCHANT.fetch("id"),
        "issued_at" => now, "expires_at" => now + 600})
    end

    def order(order_id:, quantity: 3, unit_price: 800)
      amount = quantity * unit_price
      immutable({"id" => order_id, "merchant" => MERCHANT, "status" => "ready_for_complete",
        "currency" => "JPY", "line_items" => [{"id" => "tea-line", "item" => {
          "id" => "tea", "title" => "Tea", "price" => unit_price}, "quantity" => quantity,
          "totals" => totals(amount)}], "totals" => totals(amount), "links" => []})
    end

    def sign_order(order:, merchant_key:)
      M::CheckoutJWT.sign(checkout: order, profile_ref: PROFILE,
        signer: signer(merchant_key), public_key_pem: merchant_key.public_to_pem).jwt
    end

    def trust(approval:, public_keys:, now:)
      records = {"Issuer" => [:provider, "issuer"], "Agent" => [:agent, "agent"],
        "Merchant" => [:merchant, MERCHANT.fetch("id")]}.map do |role, (key, identity)|
        {"role" => role, "identity" => identity, "tenant_id" => TENANT, "purpose" => "checkout",
          "key_ref" => role.downcase, "public_key_pem" => public_keys.fetch(key), "active" => true,
          "not_before" => approval.fetch("issued_at"), "not_after" => approval.fetch("expires_at")}
      end
      selectors = records.to_h { |r| [r.fetch("role").downcase.to_sym, r.slice("identity", "purpose", "key_ref")] }
      M::InputBuilder.trust(snapshot: {"id" => "tea-registry", "policy_version" => "1", "active" => true,
        "not_before" => approval.fetch("issued_at"), "not_after" => approval.fetch("expires_at"), "records" => records},
        tenant_id: TENANT, verified_at: now, profile_ref: PROFILE, **selectors)
    end

    # order and checkout_jwt here are the seller's saved authoritative offer,
    # NOT values decoded from an incoming buyer presentation.
    def host_inputs(approval:, order:, checkout_jwt:, public_keys:, now:)
      {trust: trust(approval: approval, public_keys: public_keys, now: now),
        order: {"tenant_id" => TENANT, "buyer_account_id" => "demo-buyer", "order_id" => order.fetch("id"),
          "merchant_id" => MERCHANT.fetch("id"), "audience" => AUDIENCE, "order_version" => "1",
          "currency" => order.fetch("currency"), "expected_total" => order.fetch("totals").find { |v| v.fetch("type") == "total" }.fetch("amount")},
        root_presentation: approval.fetch("checkout_open"), host_checkout_jws: checkout_jwt}
    end

    def prepare(approval:, order:, checkout_jwt:, public_keys:, nonce:, now:)
      M::InputBuilder.prepare(**host_inputs(approval: approval, order: order, checkout_jwt: checkout_jwt,
        public_keys: public_keys, now: now), challenge_id: "#{approval.fetch('approval_id')}/#{order.fetch('id')}",
        nonce: nonce, issuer_id: "tea-host", not_before: now,
        not_after: [now + 300, approval.fetch("expires_at")].min)
    end

    def payment_details(checkout_jwt:, public_keys:)
      M::Payment.details(checkout_jwt: checkout_jwt, trusted_merchant_public_key_pem: public_keys.fetch(:merchant),
        expected_merchant_id: MERCHANT.fetch("id"), payment_instrument: INSTRUMENT)
    end

    # Only the buyer Agent signer is available. Invalid quantity fails at
    # Checkout issuance; over-budget fails at Payment issuance, before signing.
    def close(approval:, checkout_jwt:, agent_key:, public_keys:, nonce:, now:)
      checkout = M::ConditionalCheckout.issue_closed(root_presentation: approval.fetch("checkout_open"),
        checkout_jwt: checkout_jwt, trusted_issuer_public_key_pem: public_keys.fetch(:provider),
        agent_public_key_pem: public_keys.fetch(:agent), trusted_merchant_public_key_pem: public_keys.fetch(:merchant),
        expected_merchant_id: MERCHANT.fetch("id"), audience: AUDIENCE, nonce: nonce,
        verified_at: now, signer: signer(agent_key))
      checkout = M::ConditionalCheckout.present(root_presentation: checkout.root_presentation,
        terminal_jws: checkout.terminal_jws, checkout_jwt: checkout.checkout_jwt)
      payment = M::Payment.issue_closed(open_sd_jwt: approval.fetch("payment_open"),
        payment: payment_details(checkout_jwt: checkout_jwt, public_keys: public_keys),
        trusted_provider_public_key_pem: public_keys.fetch(:provider), agent_public_key_pem: public_keys.fetch(:agent),
        audience: AUDIENCE, nonce: "#{nonce}/payment", verified_at: now, signer: signer(agent_key))
      payment = M::Payment.present(open_sd_jwt: payment.open_sd_jwt, closed_sd_jwt: payment.closed_sd_jwt)
      immutable({"checkout_open" => checkout.root_presentation, "checkout_terminal" => checkout.terminal_jws,
        "checkout_jwt" => checkout.checkout_jwt, "payment_open" => payment.open_sd_jwt,
        "payment_closed" => payment.closed_sd_jwt})
    rescue M::ConditionalCheckout::Invalid
      raise Invalid.new(:checkout_refused), cause: nil
    rescue M::Payment::Invalid
      raise Invalid.new(:payment_refused), cause: nil
    end

    def verification_inputs(approval:, order:, checkout_jwt:, wires:, saved_challenge:, public_keys:, nonce:, now:)
      # Refuse substitution, even before complete SDK verification.
      raise ArgumentError, "presentation differs from saved offer" unless
        wires.fetch("checkout_open") == approval.fetch("checkout_open") &&
        wires.fetch("payment_open") == approval.fetch("payment_open") && wires.fetch("checkout_jwt") == checkout_jwt
      raw = M::InputBuilder.inputs(**host_inputs(approval: approval, order: order, checkout_jwt: checkout_jwt,
        public_keys: public_keys, now: now), terminal_jws: wires.fetch("checkout_terminal"),
        saved_challenge: M::InputBuilder.restore(saved_challenge: saved_challenge),
        expected_challenge_issuer_id: "tea-host", clock_source_id: "demo-clock", verified_at: now)
      {closed_sd_jwt: wires.fetch("payment_closed"), open_sd_jwt: wires.fetch("payment_open"),
        checkout_mode: :conditional, checkout_inputs: raw,
        expected_payment: payment_details(checkout_jwt: checkout_jwt, public_keys: public_keys),
        trusted_provider_public_key_pem: public_keys.fetch(:provider), expected_agent_public_key_pem: public_keys.fetch(:agent),
        expected_audience: AUDIENCE, expected_nonce: "#{nonce}/payment", verified_at: now}
    end

    def receipt_context(payment_id:, merchant_public_key_pem:, not_before:, not_after:)
      {trusted_public_key_pem: merchant_public_key_pem, expected_issuer: RECEIPT_ISSUER,
        expected_payment_id: payment_id, not_before: not_before, not_after: not_after}
    end

    def sign_receipt(closed_sd_jwt:, payment_id:, merchant_key:, now:, outcome: "Success")
      fields = case outcome
      when "Success" then {psp_confirmation_id: "mock/#{payment_id}", network_confirmation_id: "mock-network/#{payment_id}"}
      when "Error" then {error: "mock_declined", error_description: "Synthetic processor decline"}
      else raise ArgumentError, "unsupported outcome"
      end
      M::PaymentReceipt.sign(closed_sd_jwt: closed_sd_jwt, issuer: RECEIPT_ISSUER,
        payment_id: payment_id, outcome: outcome, issued_at: now, **fields,
        signer: signer(merchant_key), public_key_pem: merchant_key.public_to_pem).jwt
    end

    def receipt(**arguments) = sign_receipt(**arguments)

    def verify_receipt(receipt_jwt:, closed_sd_jwt:, context:, now:)
      M::PaymentReceipt.verify(jwt: receipt_jwt, closed_sd_jwt: closed_sd_jwt, **context, verified_at: now)
    end
  end
end
