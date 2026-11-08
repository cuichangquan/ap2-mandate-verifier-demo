require "bundler/setup"
require "rails"
require "action_controller/railtie"
require "securerandom"
require_relative "../app/services/scenario_verifier"
require_relative "../app/services/multi_item_scenario"

module PurchaseDemo
  class Application < Rails::Application
    config.load_defaults 8.0
    config.eager_load = false
    config.i18n.available_locales = [:en, :ja]
    config.i18n.default_locale = :en
    # Bounded, local presentation snapshots: switching language never re-runs
    # verification/signing, and cookies contain only opaque snapshot IDs.
    config.cache_store = :memory_store, { size: 16.megabytes }
    config.secret_key_base = SecureRandom.hex(64)
    config.hosts = ["localhost", "127.0.0.1"]
    config.action_controller.allow_forgery_protection = true
    config.filter_parameters += [:authenticity_token]
    config.action_dispatch.default_headers.merge!(
      "Content-Security-Policy" => "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'",
      "Referrer-Policy" => "same-origin")
    routes.append do
      root "demo#index"
      get "/merchant", to: "demo#merchant"
      get "/multi-item", to: "demo#multi_item"
      post "/verify", to: "demo#verify"
    end
  end
end
PurchaseDemo::Application.initialize!
