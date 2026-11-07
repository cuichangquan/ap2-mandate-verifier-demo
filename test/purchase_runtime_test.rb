# frozen_string_literal: true
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "jwt"
require "base64"
require "digest"
require_relative "../purchase_demo/runtime"

# In-process role integration: only the Transport boundary is replaced. These
# tests do NOT establish TLS, A2A HTTP interoperability or container isolation.
class PurchaseRuntimeTest < Minitest::Test
  D = PurchaseDemo
  NOW = 1_800_000_000

  module LocalIdentity
    def initialize(local_dir:, local_key:, local_public:, **arguments)
      @local_dir, @local_key, @local_public = local_dir, local_key, local_public
      super(**arguments)
    end
    def keys = @local_public
    def key = @local_key
  end
  class LocalSeller < D::Seller
    include LocalIdentity
    def with_acceptance
      ledger = AP2MandateVerifier::PaymentAcceptance::SQLiteStore.new(path: File.join(@local_dir, "acceptance.sqlite3"))
      yield ledger, AP2MandateVerifier::PaymentAcceptance::Service.new(store: ledger)
    ensure
      ledger&.close
    end
  end
  class LocalBuyer < D::Buyer
    include LocalIdentity
  end
  class LocalAuthority < D::Authority
    include LocalIdentity
  end
  class InProcessTransport
    attr_accessor :seller, :buyer
    def request(service:, path:, payload:)
      raise D::Transport::Error unless path == "/control"
      case service
      when "seller" then seller.provision(copy(payload))
      when "buyer" then buyer.control(copy(payload))
      else raise D::Transport::Error
      end
    end
    def a2a(command:, payload:) = copy(seller.call(command, copy(payload)))
    def copy(value) = JSON.parse(JSON.generate(value))
  end

  def setup
    @root = Dir.mktmpdir("purchase-role-test-")
    @dirs = %w[authority buyer seller].to_h { |role| [role, File.join(@root, role)] }
    @dirs.each { |role, dir| D::Store.bootstrap(role: role, state_dir: dir) }
    @private = %w[authority buyer seller].to_h { |role| [role, OpenSSL::PKey::EC.generate("prime256v1")] }
    @public = {provider: @private.fetch("authority").public_to_pem,
      agent: @private.fetch("buyer").public_to_pem, merchant: @private.fetch("seller").public_to_pem}
    @clock = NOW
    @transport = InProcessTransport.new
    reopen
  end

  def teardown
    FileUtils.remove_entry(@root) if @root && File.directory?(@root)
  end

  def reopen
    @stores = @dirs.transform_values { |dir| D::Store.new(state_dir: dir) }
    roles = {"seller" => LocalSeller, "buyer" => LocalBuyer, "authority" => LocalAuthority}
    @roles = roles.to_h do |name, klass|
      [name, klass.new(local_dir: @dirs.fetch(name), local_key: @private.fetch(name), local_public: @public,
        store: @stores.fetch(name), transport: @transport, clock: -> { @clock })]
    end
    @transport.seller, @transport.buyer = @roles.values_at("seller", "buyer")
  end

  def approve(scenario = "valid")
    id = SecureRandom.uuid
    @roles.fetch("authority").approve(id: id, scenario: scenario)
    id
  end
  def run_purchase(id) = @roles.fetch("authority").run(id: id)
  def count(id) = @stores.fetch("seller").processor(id)&.fetch("execution_count") || 0

  def buyer_wires(id)
    row = @stores.fetch("buyer").read(id)
    offer = @roles.fetch("seller").call("offer", {"purchase_id" => id})
    D::Protocol.close(approval: row.fetch("approval"), checkout_jwt: offer.fetch("checkout_jwt"),
      agent_key: @private.fetch("buyer"), public_keys: @public, nonce: offer.fetch("nonce"), now: @clock)
  end

  def test_full_roles_success_retry_and_reopen_preserve_first_wire
    id = approve
    first = run_purchase(id)
    assert_equal "真正なSuccess・購入成功通知", first.fetch("receipt_status")
    assert_equal 1, count(id)
    wires = @stores.fetch("buyer").read(id).fetch("wires")
    reopen
    @clock += 601 # Lookup/reconciliation remains possible after Mandate expiry.
    status = @roles.fetch("authority").status(id: id)
    assert_equal "真正なSuccess・購入成功通知", status.fetch("receipt_status")
    run_purchase(id)
    assert wires == @stores.fetch("buyer").read(id).fetch("wires"), "first signed originals changed"
    assert_equal 1, count(id)
  end

  def test_concurrent_same_business_purchase_has_one_mock_effect
    id = approve
    wires = buyer_wires(id)
    # Separate role instances/connections against the same authoritative files.
    sellers = 4.times.map do
      LocalSeller.new(local_dir: @dirs.fetch("seller"), local_key: @private.fetch("seller"), local_public: @public,
        store: D::Store.new(state_dir: @dirs.fetch("seller")), clock: -> { @clock })
    end
    ready, start = Queue.new, Queue.new
    threads = sellers.map do |seller|
      Thread.new do
        ready << true
        start.pop
        seller.call("purchase", {"purchase_id" => id, "wires" => wires})
      end
    end
    sellers.length.times { ready.pop }
    sellers.length.times { start << true }
    results = threads.map(&:value)
    assert_equal 4, results.length
    assert_equal 1, count(id)
    assert_equal "receipt_success", @roles.fetch("seller").status(id).fetch("acceptance_state")
    # A freshly signed equivalent instruction does not create another operation.
    @roles.fetch("seller").call("purchase", {"purchase_id" => id, "wires" => buyer_wires(id)})
    assert_equal 1, count(id)
  end

  def test_signed_quantity_budget_and_tamper_never_charge
    %w[quantity budget tampered].each do |scenario|
      id = approve(scenario)
      output = run_purchase(id)
      assert_equal 0, count(id), scenario
      assert_equal "未開始", output.fetch("payment_status"), scenario
      refute_equal "真正なSuccess・購入成功通知", output.fetch("receipt_status"), scenario
    end
  end

  def test_error_and_invalid_receipts_do_not_become_buyer_success
    {"error" => "真正なError・購入成功ではない", "wrong_receipt" => "拒否・この購入の真正なReceiptではない",
      "invalid_receipt" => "拒否・この購入の真正なReceiptではない"}.each do |scenario, expected|
      id = approve(scenario)
      result = run_purchase(id)
      assert_equal expected, result.fetch("receipt_status")
      refute_includes result.fetch("payment_status"), "模擬成功"
      run_purchase(id)
      assert_equal 1, count(id)
    end
  end

  def test_timeout_reconciliation_after_reopen_never_reexecutes
    id = approve("timeout")
    result = run_purchase(id) # Actual seller branch sleeps; fake transport does not time out.
    assert_equal "未確認", result.fetch("receipt_status")
    assert_equal 1, count(id)
    reopen
    result = @roles.fetch("authority").recover(id: id)
    assert_equal "真正なSuccess・購入成功通知", result.fetch("receipt_status")
    assert_equal 1, count(id)
  end

  def test_processing_crash_window_reconciles_persisted_mock_receipt
    id = approve
    row = @stores.fetch("seller").read(id)
    seller = @roles.fetch("seller")
    wires = buyer_wires(id)
    # Public acceptance calls model a worker stopping between PSP persistence
    # and finish, without monkey-patching cryptography or storage.
    seller.with_acceptance do |ledger, service|
      ledger.authorize!(**seller.scope(row), mode: :conditional, profile_ref: AP2MandateVerifier::Payment::PROFILE_REF,
        checkout: row.fetch("order"), payment: D::Protocol.payment_details(checkout_jwt: row.fetch("checkout_jwt"), public_keys: @public),
        receipt_context: seller.receipt_context(row))
      accepted = service.accept(**seller.scope(row), mode: :conditional, verification_inputs: seller.verification(row, wires))
      refute_nil accepted.ticket
      execution = service.start(ticket: accepted.ticket, verification_inputs: seller.verification(row, wires))
      refute_nil execution
      receipt = D::Protocol.receipt(closed_sd_jwt: execution.closed_sd_jwt, payment_id: id,
        merchant_key: @private.fetch("seller"), now: @clock, outcome: "Success")
      @stores.fetch("seller").process_once(id: id, processor_key: execution.processor_key,
        result: {"receipt_jwt" => receipt, "outcome" => "Success"})
      assert_equal :pending, service.lookup(**seller.scope(row)).status
    end
    reopen
    result = @roles.fetch("seller").recover(id)
    assert_equal "receipt_success", result.fetch("acceptance_state")
    assert_equal 1, count(id)
  end

  def wire_hash(wire) = Base64.urlsafe_encode64(Digest::SHA256.digest(wire), padding: false)

  # Test-only malicious Agent: public JWT signing deliberately bypasses the
  # safe issuance API, while preserving the original approved signed Opens.
  def malicious_wires(row)
    approval = row.fetch("approval")
    jwt = row.fetch("checkout_jwt")
    checkout_claims = {"aud" => D::Protocol::AUDIENCE, "nonce" => row.fetch("nonce"), "iat" => @clock,
      "sd_hash" => wire_hash(approval.fetch("checkout_open")), "delegate_payload" => [{
        "vct" => "mandate.checkout.1", "iat" => approval.fetch("issued_at"), "exp" => approval.fetch("expires_at"),
        "checkout_jwt" => jwt, "checkout_hash" => wire_hash(jwt)}]}
    payment = {"transaction_id" => wire_hash(jwt), "payee" => row.fetch("order").fetch("merchant"),
      "payment_instrument" => D::Protocol::INSTRUMENT,
      "payment_amount" => {"currency" => "JPY", "amount" => row.fetch("order").fetch("totals").last.fetch("amount")},
      "vct" => "mandate.payment.1", "iat" => @clock, "exp" => approval.fetch("expires_at")}
    payment_claims = {"aud" => D::Protocol::AUDIENCE, "nonce" => "#{row.fetch('nonce')}/payment", "iat" => @clock,
      "sd_hash" => wire_hash(approval.fetch("payment_open")), "delegate_payload" => [payment]}
    checkout_terminal, payment_terminal = [checkout_claims, payment_claims].map do |claims|
      signed = JWT.encode(claims, @private.fetch("buyer"), "ES256", {"typ" => "kb+sd-jwt"})
      verified, header = JWT.decode(signed, OpenSSL::PKey.read(@public.fetch(:agent)), true,
        algorithms: ["ES256"], verify_expiration: false, verify_not_before: false, verify_iat: false)
      assert claims == verified, "independently verified signature payload differs"
      assert_equal "kb+sd-jwt", header.fetch("typ")
      signed
    end
    {"checkout_open" => approval.fetch("checkout_open"), "checkout_terminal" => checkout_terminal,
      "checkout_jwt" => jwt, "payment_open" => approval.fetch("payment_open"), "payment_closed" => payment_terminal + "~"}
  end

  def test_handcrafted_malicious_fixture_has_a_fully_valid_control
    id = approve("valid")
    row = @stores.fetch("seller").read(id)
    wires = malicious_wires(row)
    inputs = @roles.fetch("seller").verification(row, wires)
    assert AP2MandateVerifier.verify_checkout(**inputs.fetch(:checkout_inputs)).success?, "same fixture builder must pass full Checkout for valid terms"
    assert AP2MandateVerifier::Payment.verify(**inputs).verified?, "same fixture builder must pass full Payment for valid terms"
    assert_equal 0, count(id)
  end

  def test_authentically_signed_bad_full_chains_reject_at_merchant_without_charge
    %w[quantity budget].each do |scenario|
      id = approve(scenario)
      row = @stores.fetch("seller").read(id)
      wires = malicious_wires(row)
      # Independent signature checks cover original Provider Opens and merchant
      # order too; these are not corrupt-byte/signature-negative test cases.
      [[wires.fetch("checkout_open").split("~").first, :provider],
       [wires.fetch("payment_open").split("~").first, :provider],
       [wires.fetch("checkout_jwt"), :merchant]].each do |jwt, role|
        claims, = JWT.decode(jwt, OpenSSL::PKey.read(@public.fetch(role)), true,
          algorithms: ["ES256"], verify_expiration: false, verify_not_before: false, verify_iat: false)
        assert_kind_of Hash, claims
      end
      assert row.fetch("approval").fetch("checkout_open") == wires.fetch("checkout_open"), "approved Checkout Open changed"
      assert row.fetch("approval").fetch("payment_open") == wires.fetch("payment_open"), "approved Payment Open changed"
      seller = @roles.fetch("seller")
      inputs = seller.verification(row, wires)
      checkout = AP2MandateVerifier.verify_checkout(**inputs.fetch(:checkout_inputs))
      if scenario == "quantity"
        refute checkout.success?
        assert_equal :constraint_mismatch, checkout.code
        assert_equal 2, row.fetch("order").fetch("line_items").first.fetch("quantity")
      else
        assert checkout.success?, "budget negative must pass full Checkout first"
        assert_equal 3600, inputs.fetch(:expected_payment).fetch("payment_amount").fetch("amount")
      end
      refute AP2MandateVerifier::Payment.verify(**inputs).verified?
      result = seller.call("purchase", {"purchase_id" => id, "wires" => wires})
      assert_equal "拒否", result.fetch("summary").fetch("ap2_status")
      assert_equal 0, count(id)
      assert_nil @stores.fetch("seller").processor(id)
    end
  end

  def test_buyer_does_not_trust_success_summary_without_success_receipt
    id = approve
    wires = buyer_wires(id)
    @stores.fetch("buyer").update(id) { |r| r.merge("wires" => wires) }
    buyer = @roles.fetch("buyer")
    row = @stores.fetch("buyer").read(id)
    misleading = {"summary" => {"ap2_status" => "検証成功", "app_status" => "永続受理済み・再実行不可",
      "payment_status" => "模擬成功", "execution_count" => 1, "reason" => "success claimed"}}
    output = buyer.consume(row, misleading)
    refute_includes output.fetch("summary").fetch("payment_status"), "模擬成功"
    assert_equal "未確認", output.fetch("summary").fetch("receipt_status")
    error = D::Protocol.receipt(closed_sd_jwt: wires.fetch("payment_closed"), payment_id: id,
      outcome: "Error", merchant_key: @private.fetch("seller"), now: @clock)
    output = buyer.consume(row, misleading.merge("receipt_jwt" => error))
    assert_includes output.fetch("summary").fetch("payment_status"), "模擬失敗"
    assert_equal "真正なError・購入成功ではない", output.fetch("summary").fetch("receipt_status")
  end

  class FinishUnavailableSeller < LocalSeller
    Failure = Struct.new(:status, :processor_key, :receipt_jwt)
    def with_acceptance
      super do |ledger, service|
        # Fault injection ONLY for the post-effect finish result. It conveys no
        # verification evidence or execution capability, and performs no commit.
        service.define_singleton_method(:finish) { |**_args| Failure.new(:unavailable, nil, nil) }
        yield ledger, service
      end
    end
  end

  def test_unavailable_finish_after_mock_effect_is_unknown_then_reconciled
    id = approve
    faulty = FinishUnavailableSeller.new(local_dir: @dirs.fetch("seller"), local_key: @private.fetch("seller"),
      local_public: @public, store: @stores.fetch("seller"), clock: -> { @clock })
    result = faulty.call("purchase", {"purchase_id" => id, "wires" => buyer_wires(id)})
    assert_equal 1, count(id)
    assert_equal "unavailable", result.fetch("acceptance_state")
    refute_equal "未開始", result.fetch("summary").fetch("payment_status")
    refute_equal "承認済み・未受理", result.fetch("summary").fetch("app_status")
    reopen
    recovered = @roles.fetch("seller").recover(id)
    assert_equal "receipt_success", recovered.fetch("acceptance_state")
    assert_equal 1, count(id)
  end

  def test_missing_databases_fail_closed_without_reset
    id = approve
    wires = buyer_wires(id)
    path = File.join(@dirs.fetch("seller"), "acceptance.sqlite3")
    File.rename(path, path + ".saved")
    assert_raises(AP2MandateVerifier::PaymentAcceptance::Unavailable) do
      @roles.fetch("seller").call("purchase", {"purchase_id" => id, "wires" => wires})
    end
    refute File.exist?(path)
    assert_equal 0, count(id)
    state = File.join(@dirs.fetch("buyer"), "state.sqlite3")
    File.rename(state, state + ".saved")
    assert_raises(D::Store::Unavailable) { D::Store.new(state_dir: @dirs.fetch("buyer")) }
    refute File.exist?(state)
  end

  def test_application_current_state_can_reject_cryptographically_valid_purchase
    id = approve
    wires = buyer_wires(id)
    seller = @roles.fetch("seller")
    row = @stores.fetch("seller").read(id)
    assert AP2MandateVerifier::Payment.verify(**seller.verification(row, wires)).verified?, "fixture must pass complete AP2 verification"
    @stores.fetch("seller").update(id) { |record| record.merge("active" => false) }
    result = seller.call("purchase", {"purchase_id" => id, "wires" => wires})
    assert_equal "検証成功", result.fetch("summary").fetch("ap2_status")
    assert_equal "拒否・未受理", result.fetch("summary").fetch("app_status")
    assert_equal "未開始", result.fetch("summary").fetch("payment_status")
    assert_equal 0, count(id)
  end

  def test_current_application_state_is_reread_before_start
    id = approve
    wires = buyer_wires(id)
    changed_seller = Class.new(LocalSeller) do
      def application_allows?(row)
        allowed = super
        @application_checks = (@application_checks || 0) + 1
        # Deterministic protected-state race after first ALLOW, before start.
        @store.update(row.fetch("id")) { |record| record.merge("active" => false) } if @application_checks == 1
        allowed
      end
    end.new(local_dir: @dirs.fetch("seller"), local_key: @private.fetch("seller"), local_public: @public,
      store: @stores.fetch("seller"), clock: -> { @clock })
    result = changed_seller.call("purchase", {"purchase_id" => id, "wires" => wires})
    assert_equal "実行拒否・受理予約保持", result.fetch("summary").fetch("app_status")
    assert_equal 0, count(id)
    # Reservation is retained rather than returned as a new permission.
    assert_equal "pending", @roles.fetch("seller").status(id).fetch("acceptance_state")
  end

  def test_ui_projection_excludes_keys_nonces_and_signed_wires
    id = approve
    output = run_purchase(id)
    text = JSON.generate(output)
    assert_equal %w[ap2_status app_status approval execution_count offer payment_status purchase_id reason receipt_status scenario].sort, output.keys.sort
    %w[authority buyer seller].each do |role|
      refute text.include?(@private.fetch(role).private_to_pem), "private key in public summary"
      @stores.fetch(role).read(id).each do |name, value|
        refute text.include?(value), "protected value in public summary" if %w[nonce checkout_jwt saved_challenge].include?(name)
      end
    end
    @stores.fetch("buyer").read(id).fetch("wires").each_value { |wire| refute text.include?(wire), "signed wire in public summary" }
    refute text.match?(/PRIVATE KEY|receipt_jwt|processor_key|checkout_open|payment_closed/), "protected field in public summary"
  end
end
