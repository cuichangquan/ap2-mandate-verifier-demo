# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../purchase_demo/setup'
require_relative '../purchase_demo/readiness'
require_relative '../purchase_demo/buyer_application'
require 'rack/mock'

class PurchaseReadinessTest < Minitest::Test
  D = PurchaseDemo
  def setup
    @root = Dir.mktmpdir('readiness-')
    @state = File.join(@root, 'state')
    @trust = File.join(@root, 'trust')
    FileUtils.mkdir_p([@state, @trust])
    @clock = Time.now
    @role = 'buyer'
    D::Store.bootstrap(role: @role, state_dir: @state)
    %w[authority buyer seller].each do |role|
      key = OpenSSL::PKey::EC.generate('prime256v1')
      File.write(File.join(@trust, "#{role}.pub.pem"), key.public_to_pem)
      File.write(File.join(@state, 'signing_key.pem'), key.private_to_pem, mode: 'w', perm: 0o600) if role == @role
    end
    %w[buyer_control seller_a2a].each { |token| File.write(File.join(@state, "#{token}.token"), 'a' * 64, mode: 'w', perm: 0o600) }
    ca_key = OpenSSL::PKey::EC.generate('prime256v1')
    ca = D::Setup.certificate('purchase-demo-ca', ca_key, nil, nil, ca: true)
    key = OpenSSL::PKey::EC.generate('prime256v1')
    cert = D::Setup.certificate('buyer', key, ca, ca_key)
    File.write(File.join(@trust, 'ca.crt'), ca.to_pem)
    File.write(File.join(@trust, '.initialized'), '1')
    File.write(File.join(@state, 'tls.key'), key.private_to_pem, mode: 'w', perm: 0o600)
    File.write(File.join(@state, 'tls.crt'), cert.to_pem, mode: 'w', perm: 0o600)
    @peer = {'role' => 'seller', 'status' => 'ready', 'ready' => true}
    @probes = []
  end

  def teardown = FileUtils.remove_entry(@root)
  def readiness
    D::Readiness.new(role: @role, state_dir: @state, trust_dir: @trust, clock: -> { @clock },
      probe: ->(peer) { @probes << peer; @peer })
  end

  def test_local_health_and_dependencies
    assert readiness.local['ready']
    assert_empty @probes
    report = readiness.report
    assert report['ready']
    assert_equal ['seller'], @probes
    assert report['operations']['run']
  end

  def test_dependency_outage_blocks_run_but_not_provision_and_never_changes_records
    before = File.binread(File.join(@state, 'state.sqlite3'))
    @peer = {'role' => 'seller', 'status' => 'unreachable', 'ready' => false}
    report = readiness.report
    refute report['ready']
    assert report['operations']['provision']
    refute report['operations']['run']
    assert_raises(D::Readiness::Unavailable) { readiness.require!('run') }
    assert_equal before, File.binread(File.join(@state, 'state.sqlite3'))
    @peer = {'role' => 'seller', 'status' => 'ready', 'ready' => true}
    assert readiness.report['operations']['run']
  end

  def test_expiring_certificate_is_warning_and_expired_blocks
    @clock += 6 * 86_400
    assert readiness.local['ready']
    assert_includes readiness.local.dig('tls', 'reasons'), 'expiring'
    @clock += 2 * 86_400
    report = readiness.local
    refute report['ready']
    assert_equal 'certificate_update_required', report['status']
  end

  def test_pending_rotation_blocks_every_operation
    File.write(File.join(@trust, '.tls-rotation.json'), '{}')
    refute readiness.local['ready']
    refute readiness.report['operations'].values.any?
  end

  def test_missing_initialization_and_key_mismatch
    File.unlink(File.join(@trust, '.initialized'))
    assert_equal 'preparing', readiness.local['status']
    File.write(File.join(@trust, '.initialized'), '1')
    File.write(File.join(@state, 'tls.key'), OpenSSL::PKey::EC.generate('prime256v1').private_to_pem)
    assert_equal 'certificate_update_required', readiness.local['status']
  end

  def test_missing_database_is_not_created
    File.unlink(File.join(@state, 'state.sqlite3'))
    refute readiness.local['ready']
    refute File.exist?(File.join(@state, 'state.sqlite3'))
  end

  def test_diagnostics_do_not_return_secrets
    output = JSON.generate(readiness.report)
    refute_includes output, 'PRIVATE KEY'
    refute_includes output, 'a' * 64
    refute_includes output, 'signing_key.pem'
  end
  def test_direct_buyer_post_is_blocked_during_maintenance
    old_state, old_trust = ENV['PURCHASE_STATE_DIR'], ENV['PURCHASE_TRUST_DIR']
    ENV['PURCHASE_STATE_DIR'], ENV['PURCHASE_TRUST_DIR'] = @state, @trust
    File.write(File.join(@trust, '.tls-rotation.json'), '{}')
    response = Rack::MockRequest.new(D::BuyerApplication.new).post('/control',
      'CONTENT_TYPE' => 'application/json', 'HTTP_AUTHORIZATION' => "Bearer #{'a' * 64}",
      input: JSON.generate('command' => 'provision', 'purchase_id' => SecureRandom.uuid))
    assert_equal 503, response.status
    assert_empty D::Store.new(state_dir: @state).list
  ensure
    old_state ? ENV['PURCHASE_STATE_DIR'] = old_state : ENV.delete('PURCHASE_STATE_DIR')
    old_trust ? ENV['PURCHASE_TRUST_DIR'] = old_trust : ENV.delete('PURCHASE_TRUST_DIR')
  end

  def test_healthcheck_requires_live_listener_not_only_files
    ready = D::Readiness.new(role: @role, state_dir: @state, trust_dir: @trust,
      probe: ->(peer) { {'role' => peer, 'ready' => peer != 'buyer', 'status' => peer == 'buyer' ? 'unreachable' : 'ready'} })
    assert ready.report['ready']
    refute ready.healthcheck['ready']
    assert_equal 'unreachable', ready.healthcheck.dig('listener', 'status')
  end

end
