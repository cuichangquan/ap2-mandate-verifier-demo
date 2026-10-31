# frozen_string_literal: true
# Published 0.5.0; synthetic keys and application outcomes only.
module MerchantScenario
  def self.call
    require "ap2_mandate_verifier"
    require "openssl"
    require "jwt"
    merchant = OpenSSL::PKey::EC.generate("prime256v1")
    agent = OpenSSL::PKey::EC.generate("prime256v1")
    now = 1_800_000_000
    totals = [{"type" => "subtotal", "amount" => 100}, {"type" => "total", "amount" => 100}]
    checkout = {"id" => "sample-order", "merchant" => {"id" => "shop", "name" => "Demo shop"},
      "status" => "ready_for_complete", "currency" => "USD", "links" => [], "totals" => totals,
      "line_items" => [{"id" => "line", "item" => {"id" => "sku", "title" => "Sample", "price" => 100},
        "quantity" => 1, "totals" => totals}]}
    c = AP2MandateVerifier::CheckoutJWT
    signed = c.sign(checkout: checkout, signer: c.es256_signer(private_key: merchant), public_key_pem: merchant.public_to_pem)
    # Test-only authorization envelope, never a product Mandate issuance API.
    closed = {"vct" => "mandate.checkout.1", "iat" => now, "exp" => now + 60,
      "checkout_jwt" => signed.jwt, "checkout_hash" => signed.checkout_hash}
    terminal = JWT.encode({"aud" => "demo", "nonce" => "synthetic-only", "iat" => now,
      "sd_hash" => Base64.urlsafe_encode64(Digest::SHA256.digest("synthetic-root~"), padding: false),
      "delegate_payload" => [closed]}, agent, "ES256", {"typ" => "kb+sd-jwt"})
    wire = terminal + "~" # Explicit original final SD-JWT serialization.
    r = AP2MandateVerifier::CheckoutReceipt
    rows = %w[Success Error].map do |outcome|
      fields = outcome == "Success" ? {order_id: "sample-order"} : {error: "declined", error_description: "Application declined"}
      receipt = r.sign(closed_sd_jwt: wire, issuer: "shop", outcome: outcome, issued_at: now,
        signer: c.es256_signer(private_key: merchant), public_key_pem: merchant.public_to_pem, **fields)
      inputs = {jwt: receipt.jwt, closed_sd_jwt: wire, trusted_public_key_pem: merchant.public_to_pem,
        expected_issuer: "shop", not_before: now - 60, not_after: now + 60, verified_at: now}
      authentic = r.verify(**inputs)
      wrong = r.verify(**inputs.merge(expected_issuer: "other"))
      {outcome: authentic.outcome, verified: authentic.verified?, purchase_succeeded: authentic.purchase_succeeded?,
        purchase_rejected: authentic.purchase_rejected?, wrong_issuer_verified: wrong.verified?}
    end
    {checkout_hash: signed.checkout_hash, reference: r.reference(closed_sd_jwt: wire), rows: rows}
  end
end
