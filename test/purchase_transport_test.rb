# frozen_string_literal: true
require 'minitest/autorun'
require 'tmpdir'
require_relative '../purchase_demo/transport'

class PurchaseTransportTest < Minitest::Test
  def test_fixed_authority_routes_only
    client = PurchaseDemo::Transport.new(role: 'authority')
    [%w[seller /a2a], %w[buyer /admin], %w[127.0.0.1 /control], %w[https://evil.example /control]].each do |service, path|
      assert_raises(PurchaseDemo::Transport::Error) { client.request(service: service, path: path, payload: {}) }
    end
    assert_raises(PurchaseDemo::Transport::Error) { client.a2a(command: 'buy', payload: {}) }
  end

  def test_buyer_cannot_use_authority_control
    client = PurchaseDemo::Transport.new(role: 'buyer')
    assert_raises(PurchaseDemo::Transport::Error) { client.request(service: 'seller', path: '/control', payload: {}) }
  end

  def test_invalid_role_and_command
    assert_raises(PurchaseDemo::Transport::Error) { PurchaseDemo::Transport.new(role: 'seller') }
    client = PurchaseDemo::Transport.new(role: 'buyer')
    ['', '../buy', "buy\n", 'x' * 33].each do |command|
      assert_raises(PurchaseDemo::Transport::Error) { client.a2a(command: command, payload: {}) }
    end
  end

  def test_request_bound_before_network_or_credential
    client = PurchaseDemo::Transport.new(role: 'authority')
    error = assert_raises(PurchaseDemo::Transport::Error) { client.request(service: 'seller', path: '/control', payload: { 'large' => 'x' * 131_072 }) }
    assert_equal 'request too large', error.message
  end

  def test_local_error_does_not_expose_path_or_exception_cause
    client = PurchaseDemo::Transport.new(role: 'authority', state_dir: '/not-a-real-secret-path')
    error = assert_raises(PurchaseDemo::Transport::Error) { client.request(service: 'seller', path: '/control', payload: {}) }
    refute_includes error.message, '/not-a-real-secret-path'
    assert_nil error.cause
  end
end
