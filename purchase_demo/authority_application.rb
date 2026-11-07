# frozen_string_literal: true
require "bundler/setup"
require "rails"
require "action_controller/railtie"
require "securerandom"
require "logger"
require_relative "runtime"

module PurchaseDemo
  class AuthorityApplication < Rails::Application
    config.load_defaults 8.0
    config.root = File.expand_path("..", __dir__)
    config.eager_load = false
    config.secret_key_base = File.read(File.join(ENV.fetch("PURCHASE_STATE_DIR"), "session_secret")).strip
    config.hosts = ["localhost", "127.0.0.1"]
    config.session_store :cookie_store, key: "_tea_authority", httponly: true, same_site: :strict
    config.action_controller.allow_forgery_protection = true
    config.action_controller.forgery_protection_origin_check = true
    config.action_dispatch.show_exceptions = :none
    config.consider_all_requests_local = false
    # Wire presentations, key material, and challenge values never enter Rails logs.
    config.logger = Logger.new(File::NULL)
    config.filter_parameters += [:authenticity_token, :token, :jwt, :jws, :presentation,
      :nonce, :key, :secret, :password, :authorization, :checkout, :payment, :receipt]
    config.action_dispatch.default_headers.merge!(
      "Content-Security-Policy" => "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'",
      "Referrer-Policy" => "same-origin", "X-Content-Type-Options" => "nosniff",
      "Cache-Control" => "no-store")
    routes.append do
      root "purchase_authority#index"
      post "/approve", to: "purchase_authority#approve"
      get "/purchases/:id", to: "purchase_authority#show"
      post "/purchases/:id/run", to: "purchase_authority#run_purchase"
      post "/purchases/:id/recover", to: "purchase_authority#recover"
    end
  end
end

class PurchaseAuthorityController < ActionController::Base
  SCENARIOS = {
    "valid" => "正常系：お茶3袋・2,400円",
    "budget" => "上限超過：3,600円の提示",
    "quantity" => "数量違反：2袋の提示",
    "tampered" => "改ざんされた購入データ",
    "error" => "模擬決済がエラーを返す",
    "timeout" => "模擬決済後に応答が途切れる",
    "wrong_receipt" => "別の購入のReceipt",
    "invalid_receipt" => "署名が不正なReceipt"
  }.freeze
  prepend_view_path File.expand_path("views", __dir__)
  protect_from_forgery with: :exception
  before_action :private_response
  before_action :owned_purchase!, only: [:show, :run_purchase, :recover]
  rescue_from ActionController::InvalidAuthenticityToken, with: :invalid_request

  def index
    session[:draft_id] ||= SecureRandom.uuid
    @draft_id = session[:draft_id]
    @scenarios = SCENARIOS
    @purchases = cached_history
    render template: "index", layout: false
  end

  def approve
    id = params[:draft_id].to_s
    unless session[:draft_id].present? && id == session[:draft_id] &&
        params[:approved] == "1" && SCENARIOS.key?(params[:scenario].to_s)
      return redirect_to "/", alert: "商品・数量・上限金額を確認して承認してください。", status: :see_other
    end
    session[:approved_purchase_ids] = (Array(session[:approved_purchase_ids]) + [id]).uniq.last(20)
    purchase_id = PurchaseDemo::Runtime.authority.approve(id: id, scenario: params[:scenario].to_s)
    purchase_id = purchase_id.fetch("purchase_id") if purchase_id.is_a?(Hash)
    raise "invalid purchase identifier" unless valid_id?(purchase_id)
    session[:approved_purchase_ids] = (Array(session[:approved_purchase_ids]) + [purchase_id]).uniq.last(20)
    session.delete(:draft_id)
    redirect_to "/purchases/#{purchase_id}", notice: "この条件で購入を承認しました。実行はまだ開始していません。", status: :see_other
  rescue StandardError
    redirect_to "/", alert: "承認を保存できませんでした。状態を確認してから再度お試しください。", status: :see_other
  end

  def show
    @purchase = safe_status(params[:id])
    return head :not_found unless @purchase
    index
  end

  def run_purchase
    PurchaseDemo::Runtime.authority.run(id: params[:id])
    redirect_to "/purchases/#{params[:id]}", status: :see_other
  rescue StandardError
    redirect_to "/purchases/#{params[:id]}", alert: "実行結果を確認できませんでした。再実行前に状態を更新してください。", status: :see_other
  end

  def recover
    PurchaseDemo::Runtime.authority.recover(id: params[:id])
    redirect_to "/purchases/#{params[:id]}", notice: "保存済みの結果を照会しました。各段階の状態をご確認ください。", status: :see_other
  rescue StandardError
    redirect_to "/purchases/#{params[:id]}", alert: "復旧照会を完了できませんでした。購入IDを維持して再度確認してください。", status: :see_other
  end

  private

  def valid_id?(id)
    id.is_a?(String) && id.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
  end

  def owned_purchase!
    head :not_found unless valid_id?(params[:id]) && Array(session[:approved_purchase_ids]).include?(params[:id])
  end

  def private_response
    response.headers["Cache-Control"] = "no-store"
  end

  def invalid_request
    render plain: "フォームの有効期限が切れました。画面を再読み込みしてください。", status: :unprocessable_entity
  end

  def cached_history
    owned = Array(session[:approved_purchase_ids])
    return [] if owned.empty?
    cached = Array(PurchaseDemo::Runtime.authority.list).each_with_object({}) do |raw, rows|
      next unless raw.is_a?(Hash)
      id = raw["purchase_id"] || raw[:purchase_id]
      next unless owned.include?(id)
      rows[id] = sanitize_summary(raw, id)
    end
    owned.reverse.filter_map { |id| cached[id] }
  end

  def safe_status(id)
    sanitize_summary(PurchaseDemo::Runtime.authority.status(id: id), id)
  rescue KeyError, PurchaseDemo::BoundaryError
    nil
  end

  def sanitize_summary(raw, id)
    return unless raw.is_a?(Hash)
    raw = raw.stringify_keys
    result = raw.slice("purchase_id", "scenario", "ap2_status", "app_status", "payment_status", "receipt_status", "execution_count", "reason")
      .select { |_k, value| value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false || value.nil? }
    %w[approval offer].each do |key|
      value = raw[key]
      result[key] = value.stringify_keys.slice("item", "quantity", "currency", "max_amount", "amount")
        .select { |_k, v| v.is_a?(String) || v.is_a?(Numeric) } if value.is_a?(Hash)
    end
    result["purchase_id"] = id
    result
  end
end

PurchaseDemo::AuthorityApplication.initialize!
