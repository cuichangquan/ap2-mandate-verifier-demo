require "bundler/setup"
require "rails"
require "action_controller/railtie"
require "securerandom"
require_relative "../app/services/scenario_verifier"

module PurchaseDemo
  class Application < Rails::Application
    config.load_defaults 8.0
    config.eager_load = false
    config.secret_key_base = SecureRandom.hex(64)
    config.hosts = ["localhost", "127.0.0.1"]
    config.action_controller.allow_forgery_protection = true
    config.filter_parameters += [:authenticity_token]
    config.action_dispatch.default_headers.merge!(
      "Content-Security-Policy" => "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'",
      "Referrer-Policy" => "same-origin")
    routes.append do
      root "demo#index"
      post "/verify", to: "demo#verify"
    end
  end
end
PurchaseDemo::Application.initialize!
