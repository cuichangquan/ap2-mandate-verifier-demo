# frozen_string_literal: true
require "ap2_mandate_verifier"
require "json"
require "openssl"
require "jwt"
require "base64"
require "digest"

# Local synthetic demonstration only. This is not a Mandate issuance product.
# Private keys live in this invocation and are never written or returned.
module MultiItemScenario
  PROFILE = "ap2.checkout.single_merchant_multi_item"
  NOW = 1_800_000_000

  def self.available? = AP2MandateVerifier::TrustContext.const_defined?(:MULTI_PROFILE_REF)
  def self.hash(bytes) = Base64.urlsafe_encode64(Digest::SHA256.digest(bytes), padding: false)
  def self.totals(amount) = [{"type" => "subtotal", "amount" => amount}, {"type" => "total", "amount" => amount}]
  def self.disclose(value, salt) = Base64.urlsafe_encode64(JSON.generate([salt, value]), padding: false)
  def self.marker(disclosure) = {"..." => hash(disclosure)}

  def self.call(short_second: false)
    raise "candidate required" unless available?
    issuer, agent, merchant = Array.new(3) { OpenSSL::PKey::EC.generate("prime256v1") }
    c = AP2MandateVerifier::CheckoutJWT
    b = AP2MandateVerifier::InputBuilder
    shop = {"id" => "shop", "name" => "Demo shop"}
    products = [{"id" => "coffee", "title" => "Coffee", "price" => 120},
      {"id" => "tea", "title" => "Tea", "price" => 80}]
    quantities = [2, short_second ? 2 : 3]
    lines = products.each_with_index.map do |item, i|
      {"id" => "line-#{i + 1}", "item" => item, "quantity" => quantities[i], "totals" => totals(item["price"] * quantities[i])}
    end
    amount = lines.sum { |line| line["item"]["price"] * line["quantity"] }
    checkout = {"id" => "multi-order", "merchant" => shop, "currency" => "USD", "status" => "ready_for_complete",
      "links" => [], "line_items" => lines, "totals" => totals(amount)}
    signed = c.sign(checkout: checkout, profile_ref: PROFILE,
      signer: c.es256_signer(private_key: merchant), public_key_pem: merchant.public_to_pem)
    candidates = products.each_with_index.map { |p, i| disclose(p.slice("id", "title"), "demo-product-#{i}") }
    allowed = disclose(shop, "demo-merchant-salt")
    point = agent.public_key.to_octet_string(:uncompressed)
    jwk = {"kty" => "EC", "crv" => "P-256", "x" => Base64.urlsafe_encode64(point.byteslice(1, 32), padding: false),
      "y" => Base64.urlsafe_encode64(point.byteslice(33, 32), padding: false)}
    requirements = candidates.each_with_index.map do |candidate, i|
      {"id" => "requirement-#{i + 1}", "quantity" => [2, 3][i], "acceptable_items" => [marker(candidate)]}
    end
    opening = disclose({"vct" => "mandate.checkout.open.1", "iat" => NOW - 60, "exp" => NOW + 60,
      "cnf" => {"jwk" => jwk}, "constraints" => [{"type" => "checkout.line_items", "items" => requirements},
        {"type" => "checkout.allowed_merchants", "allowed" => [marker(allowed)]}]}, "demo-opening-salt")
    # Synthetic Issuer/Agent signatures are fixture setup, outside the Gem API.
    root_jws = JWT.encode({"delegate_payload" => [marker(opening)], "_sd_alg" => "sha-256"}, issuer,
      "ES256", {"typ" => "example+sd-jwt"})
    root = ([root_jws, opening] + candidates + [allowed, ""]).join("~")
    closed = {"vct" => "mandate.checkout.1", "iat" => NOW - 60, "exp" => NOW + 60,
      "checkout_jwt" => signed.jwt, "checkout_hash" => signed.checkout_hash}
    terminal = JWT.encode({"aud" => "demo", "nonce" => "synthetic-nonce", "iat" => NOW,
      "sd_hash" => hash(root), "delegate_payload" => [closed]}, agent, "ES256", {"typ" => "kb+sd-jwt"})
    records = %w[Issuer Agent Merchant].zip([issuer, agent, merchant]).map do |role, key|
      {"role" => role, "identity" => role == "Merchant" ? "shop" : role.downcase,
        "tenant_id" => "demo", "purpose" => "checkout", "key_ref" => role.downcase + "-1",
        "public_key_pem" => key.public_to_pem, "active" => true, "not_before" => NOW - 120, "not_after" => NOW + 120}
    end
    snapshot = {"id" => "demo-snapshot", "policy_version" => "demo-policy", "active" => true,
      "not_before" => NOW - 120, "not_after" => NOW + 120, "records" => records}
    selectors = records.to_h { |r| [r["role"].downcase.to_sym, r.slice("identity", "purpose", "key_ref")] }
    trust = b.trust(snapshot: snapshot, tenant_id: "demo", verified_at: NOW, profile_ref: PROFILE, **selectors)
    order = {"tenant_id" => "demo", "buyer_account_id" => "synthetic-buyer", "order_id" => "multi-order",
      "merchant_id" => "shop", "audience" => "demo", "order_version" => "1", "currency" => "USD",
      "expected_total" => short_second ? 400 : 480} # Independent Host expectation; never decoded from JWT.
    saved = b.prepare(trust: trust, order: order, root_presentation: root, host_checkout_jws: signed.jwt,
      challenge_id: "demo-challenge", nonce: "synthetic-nonce", issuer_id: "demo-host", not_before: NOW - 60, not_after: NOW + 60)
    restored = b.restore(saved_challenge: saved.dup)
    result = b.verify(trust: trust, saved_challenge: restored, order: order, root_presentation: root,
      terminal_jws: terminal, host_checkout_jws: signed.jwt, expected_challenge_issuer_id: "demo-host",
      clock_source_id: "synthetic-clock", verified_at: NOW)
    receipt = AP2MandateVerifier::CheckoutReceipt
    wire = terminal + "~"
    rows = %w[Success Error].map do |outcome|
      fields = outcome == "Success" ? {order_id: "multi-order"} : {error: "declined", error_description: "Synthetic application declined"}
      token = receipt.sign(closed_sd_jwt: wire, profile_ref: PROFILE, issuer: "shop", outcome: outcome, issued_at: NOW,
        signer: c.es256_signer(private_key: merchant), public_key_pem: merchant.public_to_pem, **fields)
      verified = receipt.verify(jwt: token.jwt, closed_sd_jwt: wire, profile_ref: PROFILE,
        trusted_public_key_pem: merchant.public_to_pem, expected_issuer: "shop", not_before: NOW - 60, not_after: NOW + 60, verified_at: NOW)
      {outcome: verified.outcome, verified: verified.verified?, purchase_succeeded: verified.purchase_succeeded?,
        purchase_rejected: verified.purchase_rejected?}
    end if result.success? && !short_second
    {profile: PROFILE, lines: lines, amount: amount, status: result.status, code: result.code,
      evidence_present: !result.evidence.nil?, diagnostic: result.diagnostic&.to_h(locale: :ja),
      checkout_hash: signed.checkout_hash, rows: rows || []}
  end
  private_class_method :hash, :totals, :disclose, :marker
end
