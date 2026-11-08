# frozen_string_literal: true
require "securerandom"
require "openssl"
require_relative "protocol"
require_relative "store"
require_relative "transport"
require_relative "summary_codes"

module PurchaseDemo
  SCENARIOS = %w[valid budget quantity tampered error timeout wrong_receipt invalid_receipt].freeze
  class BoundaryError < StandardError; end

  module Runtime
    module_function
    def state_dir = ENV.fetch("PURCHASE_STATE_DIR")
    def public_keys
      dir = ENV.fetch("PURCHASE_TRUST_DIR")
      {provider: "authority", agent: "buyer", merchant: "seller"}.transform_values { |role| File.binread(File.join(dir, "#{role}.pub.pem")) }
    end
    def private_key = OpenSSL::PKey.read(File.binread(File.join(state_dir, "signing_key.pem")))
    def seller = Seller.new
    def buyer = Buyer.new
    def authority = Authority.new
    def safe_summary(record)
      base = {"purchase_id" => record.fetch("id"), "scenario" => record.fetch("scenario"),
        "approval" => {"item" => "お茶", "quantity" => 3, "currency" => "JPY", "max_amount" => 3000},
        "offer" => {"quantity" => 0, "amount" => 0, "currency" => "JPY"},
        "ap2_status" => "not_run", "app_status" => "approved", "payment_status" => "not_started",
        "receipt_status" => "unverified", "execution_count" => 0, "reason" => "approval_saved"}
      summary = record.fetch("summary", {})
      base.merge(SummaryCodes.normalize(summary.slice("offer", "ap2_status", "app_status", "payment_status", "receipt_status", "execution_count", "reason")))
    end
  end

  class Role
    def initialize(store: nil, transport: nil, clock: -> { Time.now.to_i })
      @store = store || Store.new
      @transport = transport
      @clock = clock
    end
    def now = @clock.call
    def keys = Runtime.public_keys
    def key = Runtime.private_key
    def record(id) = @store.read(id) || raise(BoundaryError, "purchase unavailable")
    def summary(row) = Runtime.safe_summary(row)
    def id_from(payload)
      id = payload.fetch("purchase_id")
      raise BoundaryError unless id.is_a?(String) && Store::ID.match?(id)
      id
    end
    def terms_valid?(approval)
      approval.values_at("quantity", "max_total", "currency", "merchant_id") == [3, 3000, "JPY", "tea-shop"]
    end
  end
end
require_relative "seller"
require_relative "buyer"
require_relative "authority"
