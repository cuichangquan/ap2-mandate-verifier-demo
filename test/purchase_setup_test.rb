# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../purchase_demo/setup'

class PurchaseSetupTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir('purchase-setup-test-')
    @dirs = PurchaseDemo::Setup::ROLES.to_h { |role| [role, File.join(@root, role)] }
    @trust = File.join(@root, 'trust')
    (@dirs.values + [@trust]).each { |dir| FileUtils.mkdir_p(dir) }
    @files = PurchaseDemo::Setup.required_files(dirs: @dirs, trust: @trust)
    @files.each { |path, private_file| File.open(path, 'w', private_file ? 0o600 : 0o644) { |file| file.write('fixture') } }
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def validate = PurchaseDemo::Setup.validate_existing!(dirs: @dirs, trust: @trust)

  def test_complete_existing_layout
    assert validate
  end

  def test_every_missing_required_file_fails_without_recreation
    @files.each do |path, private_file|
      File.unlink(path)
      assert_raises(RuntimeError) { validate }
      refute File.exist?(path)
      File.open(path, 'w', private_file ? 0o600 : 0o644) { |file| file.write('fixture') }
    end
  end

  def test_publicly_readable_private_state_fails
    path = File.join(@dirs.fetch('seller'), 'acceptance.sqlite3')
    File.chmod(0o644, path)
    assert_raises(RuntimeError) { validate }
  end

  def test_empty_state_fails
    File.truncate(File.join(@dirs.fetch('buyer'), 'state.sqlite3'), 0)
    assert_raises(RuntimeError) { validate }
  end

  def test_symlinked_private_key_fails
    path = File.join(@dirs.fetch('buyer'), 'signing_key.pem')
    File.unlink(path)
    File.symlink(File.join(@dirs.fetch('authority'), 'signing_key.pem'), path)
    assert_raises(RuntimeError) { validate }
  end
end
