# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'digest'
require_relative '../purchase_demo/tls_rotate'

class PurchaseTLSRotationTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir('tls-rotation-')
    @dirs = PurchaseDemo::Setup::ROLES.to_h { |role| [role, File.join(@root, role)] }
    @trust = File.join(@root, 'trust')
    (@dirs.values + [@trust]).each { |dir| FileUtils.mkdir_p(dir) }
    PurchaseDemo::Setup.required_files(dirs: @dirs, trust: @trust).each do |path, private_file|
      File.open(path, 'w', private_file ? 0o600 : 0o644) { |f| f.write('unchanged fixture bytes') }
    end
    write_set
    @before = preserved
  end

  def teardown = FileUtils.remove_entry(@root)
  def rotation(**options) = PurchaseDemo::TLSRotation.new(dirs: @dirs, trust: @trust, **options)
  def status(role = 'buyer', **options) = PurchaseDemo::TLS.status(role: role, state_dir: @dirs.fetch(role), trust_dir: @trust, **options)
  def pending = File.exist?(File.join(@trust, PurchaseDemo::TLS::PENDING))

  def preserved
    PurchaseDemo::Setup.required_files(dirs: @dirs, trust: @trust).reject { |path, _| %w[tls.key tls.crt ca.crt].include?(File.basename(path)) }.to_h { |path, _| [path, File.binread(path)] }
  end

  def write_set(expired: false)
    ca_key = OpenSSL::PKey::EC.generate('prime256v1')
    ca = PurchaseDemo::Setup.certificate('ca', ca_key, nil, nil, ca: true)
    if expired
      ca.not_before = Time.now - 86400
      ca.not_after = Time.now - 60
      ca.sign(ca_key, OpenSSL::Digest.new('SHA256'))
    end
    File.write(File.join(@trust, 'ca.crt'), ca.to_pem)
    %w[buyer seller].each do |role|
      key = OpenSSL::PKey::EC.generate('prime256v1')
      cert = PurchaseDemo::Setup.certificate(role, key, ca, ca_key)
      if expired
        cert.not_before = Time.now - 86400
        cert.not_after = Time.now - 60
        cert.sign(ca_key, OpenSSL::Digest.new('SHA256'))
      end
      File.write(File.join(@dirs.fetch(role), 'tls.key'), key.private_to_pem)
      File.write(File.join(@dirs.fetch(role), 'tls.crt'), cert.to_pem)
    end
  end

  def test_diagnostics_before_near_and_after_expiry_without_clock_changes
    assert_equal 'ready', status['status']
    assert_includes status(now: Time.now + 6 * 86400)['reasons'], 'expiring'
    assert_equal 'ready', status(now: Time.now + 6 * 86400)['status']
    assert_includes status(now: Time.now + 8 * 86400)['reasons'], 'expired'
    assert_equal 'certificate_update_required', status(now: Time.now + 8 * 86400)['status']
  end

  def test_expired_set_rotation_preserves_every_non_tls_byte
    write_set(expired: true)
    assert_includes status['reasons'], 'expired'
    rotation.rotate!
    assert_equal @before, preserved
    %w[buyer seller].each { |role| assert_equal 'ready', status(role)['status'] }
    refute pending
    refute Dir.glob(File.join(@trust, '*')).any? { |p| File.basename(p).include?('key') }
  end

  def test_every_install_interruption_is_fail_closed_and_resumable
    (0..7).each do |step|
      assert_raises(RuntimeError) { rotation(fault: ->(n) { raise 'injected' if n == step }).rotate! }
      assert pending
      assert_includes status['reasons'], 'rotation_pending'
      assert_equal @before, preserved
      rotation.rotate!
      assert_equal 'ready', status['status']
      assert_equal @before, preserved
      refute pending
    end
  end

  def test_repeated_completed_rotation_is_safe
    2.times { rotation.rotate! }
    assert_equal @before, preserved
    assert_equal 'ready', status['status']
  end

  def test_concurrent_rotation_is_rejected
    File.open(File.join(@trust, '.tls-rotation.lock'), 'w') do |file|
      file.flock(File::LOCK_EX)
      assert_raises(RuntimeError) { rotation.rotate! }
    end
    assert_equal @before, preserved
  end

  def test_corrupted_stage_remains_blocked_until_explicit_restart
    assert_raises(RuntimeError) { rotation(fault: ->(_) { raise 'injected' }).rotate! }
    File.write(File.join(@dirs.fetch('buyer'), '.tls-next-tls.crt'), 'corrupt')
    assert_raises(RuntimeError) { rotation.rotate! }
    assert pending
    rotation.rotate!(restart: true)
    assert_equal @before, preserved
    assert_equal 'ready', status['status']
  end

  def test_key_and_ca_mismatch_are_distinguished
    File.write(File.join(@dirs.fetch('buyer'), 'tls.key'), OpenSSL::PKey::EC.generate('prime256v1').private_to_pem)
    assert_includes status['reasons'], 'key_mismatch'
    key = OpenSSL::PKey::EC.generate('prime256v1')
    File.write(File.join(@trust, 'ca.crt'), PurchaseDemo::Setup.certificate('other', key, nil, nil, ca: true).to_pem)
    assert_includes status['reasons'], 'ca_mismatch'
  end
end
