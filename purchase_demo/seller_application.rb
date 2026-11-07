# frozen_string_literal: true
require 'bundler/setup'
require 'rails'
require 'action_controller/railtie'
require 'a2a-rails'
require 'logger'
require 'json'
require 'securerandom'
require_relative 'runtime'

module PurchaseDemo
  module SellerAuthentication
    def self.valid?(header, filename)
      token = File.read(File.join(ENV.fetch('PURCHASE_STATE_DIR', '/state'), filename)).strip
      expected = "Bearer #{token}"
      header.is_a?(String) && header.bytesize == expected.bytesize &&
        ActiveSupport::SecurityUtils.secure_compare(header, expected)
    end
  end

  class PurchaseHandler
    def self.call(message:, context:)
      raise ArgumentError, 'unauthorized principal' unless context[:principal_id] == 'purchase-demo-buyer'
      command = message.fetch(:parts).first.fetch(:text)
      payload = message.fetch(:metadata).fetch('purchase_demo')
      raise ArgumentError, 'invalid payload' unless payload.is_a?(Hash)
      Runtime.seller.call(command, payload)
    end
  end

  class PurchaseAgent < A2A::Rails::Agent
    name 'Synthetic Purchase Seller'
    description 'Application-defined AP2 metadata profile over A2A 1.0; no real payments'
    version '1.0'
    skill :purchase, description: 'Evaluate synthetic purchases', tags: ['synthetic-purchase'],
      handler: PurchaseHandler, output_modes: ['application/json']
  end

  class SellerApplication < Rails::Application
    config.root = File.expand_path(__dir__)
    config.load_defaults 8.0
    config.eager_load = false
    config.secret_key_base = SecureRandom.hex(64)
    config.hosts = ['seller']
    config.logger = Logger.new(File::NULL)
    config.action_dispatch.show_exceptions = :none
    config.consider_all_requests_local = false
    config.filter_parameters += [:metadata, :payload, :authorization]
  end

  A2A::Rails.configure do |config|
    config.agent = 'PurchaseDemo::PurchaseAgent'
    config.public_base_url = 'https://seller:3443'
    config.max_request_bytes = 262_144
    config.authenticate_request = lambda do |request|
      'purchase-demo-buyer' if SellerAuthentication.valid?(request.headers['Authorization'], 'seller_a2a.token')
    end
    config.security_schemes = { 'bearer' => { 'httpAuthSecurityScheme' => { 'scheme' => 'Bearer' } } }
    config.security_requirements = [{ 'schemes' => { 'bearer' => { 'list' => [] } } }]
  end

  SellerApplication.initialize!

  # Gate the authority control route separately, never exposing its token to buyer.
  class SellerGateway
    def initialize(app = SellerApplication)
      @app = app
    end

    def call(env)
      path, method = env['PATH_INFO'], env['REQUEST_METHOD']
      return response(200, { 'ok' => true, 'role' => 'seller' }) if method == 'GET' && path == '/health'
      if method == 'POST' && path == '/control'
        return response(401, { 'error' => 'unauthorized' }) unless SellerAuthentication.valid?(env['HTTP_AUTHORIZATION'], 'seller_control.token')
        return response(415, { 'error' => 'json required' }) unless env['CONTENT_TYPE'].to_s.split(';').first == 'application/json'
        raw = env.fetch('rack.input').read(262_145)
        return response(413, { 'error' => 'request too large' }) if raw.bytesize > 262_144
        payload = JSON.parse(raw, max_nesting: 32)
        return response(400, { 'error' => 'invalid request' }) unless payload.is_a?(Hash)
        return response(200, Runtime.seller.provision(payload))
      end
      allowed = (method == 'GET' && path == '/.well-known/agent-card.json') || (method == 'POST' && path == '/a2a')
      return response(404, { 'error' => 'not found' }) unless allowed
      return response(401, { 'error' => 'unauthorized' }) unless SellerAuthentication.valid?(env['HTTP_AUTHORIZATION'], 'seller_a2a.token')
      @app.call(env)
    rescue StandardError
      response(400, { 'error' => 'request rejected' })
    end

    private

    def response(status, data)
      body = JSON.generate(data)
      [status, { 'content-type' => 'application/json', 'content-length' => body.bytesize.to_s, 'cache-control' => 'no-store' }, [body]]
    end
  end
end
