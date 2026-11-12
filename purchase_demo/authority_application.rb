# frozen_string_literal: true
require "bundler/setup"
require "rails"
require "action_controller/railtie"
require "securerandom"
require "logger"
require_relative "runtime"
require_relative "readiness"

module PurchaseDemo
  class AuthorityApplication < Rails::Application
    config.load_defaults 8.0
    config.root = File.expand_path("..", __dir__)
    config.eager_load = false
    config.i18n.available_locales = [:en, :ja]
    config.i18n.default_locale = :en
    config.i18n.load_path += Dir[File.expand_path("locales/*.yml", __dir__)]
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
      "Content-Security-Policy" => "default-src 'none'; script-src 'self'; connect-src 'self'; style-src 'unsafe-inline'; form-action 'self'; frame-ancestors 'none'; base-uri 'none'",
      "Referrer-Policy" => "same-origin", "X-Content-Type-Options" => "nosniff",
      "Cache-Control" => "no-store")
    routes.append do
      root "purchase_authority#index"
      get "/health", to: "purchase_authority#health"
      get "/ready", to: "purchase_authority#ready"
      get "/readiness.js", to: "purchase_authority#readiness_script"
      post "/approve", to: "purchase_authority#approve"
      get "/purchases/:id", to: "purchase_authority#show"
      post "/purchases/:id/run", to: "purchase_authority#run_purchase"
      post "/purchases/:id/recover", to: "purchase_authority#recover"
    end
  end
end

class PurchaseAuthorityController < ActionController::Base
  SCENARIOS = PurchaseDemo::SCENARIOS
  FLASH_CODES = %w[approval_required approval_saved approval_failed run_failed recovered recovery_failed dependencies_unavailable].freeze
  # Pending cookies from the previous UI may contain sentences instead of codes.
  # Translate exact known messages for display only; normal flash expiry is kept.
  LEGACY_FLASH = {
    "商品・数量・上限金額を確認して承認してください。" => "approval_required",
    "この条件で購入を承認しました。実行はまだ開始していません。" => "approval_saved",
    "承認を保存できませんでした。状態を確認してから再度お試しください。" => "approval_failed",
    "実行結果を確認できませんでした。再実行前に状態を更新してください。" => "run_failed",
    "保存済みの結果を照会しました。各段階の状態をご確認ください。" => "recovered",
    "復旧照会を完了できませんでした。購入IDを維持して再度確認してください。" => "recovery_failed"
  }.freeze
  helper_method :purchase_text, :purchase_path, :language_path, :status_text, :reason_text, :flash_text
  prepend_view_path File.expand_path("views", __dir__)
  protect_from_forgery with: :exception
  prepend_around_action :with_locale
  before_action :private_response
  before_action :owned_purchase!, only: [:show, :run_purchase, :recover]
  before_action :guard_operation!, only: [:approve, :run_purchase, :recover]
  rescue_from ActionController::InvalidAuthenticityToken, with: :invalid_request

  def health
    result = readiness.local
    render json: result, status: result["ready"] ? :ok : :service_unavailable
  end

  def ready
    result = readiness.report
    render json: result.merge("display" => readiness_display(result)), status: result["ready"] ? :ok : :service_unavailable
  end

  def readiness_script
    render plain: File.read(File.expand_path("views/readiness.js", __dir__)), content_type: "application/javascript"
  end

  def index
    @readiness = readiness.report
    @readiness_display = readiness_display(@readiness)
    session[:draft_id] ||= SecureRandom.uuid
    @draft_id = session[:draft_id]
    @scenarios = SCENARIOS.to_h { |code| [code, purchase_text("scenarios.#{code}")] }
    @purchases = cached_history
    render template: "index", layout: false
  end

  def approve
    id = params[:draft_id].to_s
    unless session[:draft_id].present? && id == session[:draft_id] &&
        params[:approved] == "1" && SCENARIOS.include?(params[:scenario].to_s)
      return redirect_to purchase_path("/"), alert: "approval_required", status: :see_other
    end
    session[:approved_purchase_ids] = (Array(session[:approved_purchase_ids]) + [id]).uniq.last(20)
    purchase_id = PurchaseDemo::Runtime.authority.approve(id: id, scenario: params[:scenario].to_s)
    purchase_id = purchase_id.fetch("purchase_id") if purchase_id.is_a?(Hash)
    raise "invalid purchase identifier" unless valid_id?(purchase_id)
    session[:approved_purchase_ids] = (Array(session[:approved_purchase_ids]) + [purchase_id]).uniq.last(20)
    session.delete(:draft_id)
    redirect_to purchase_path("/purchases/#{purchase_id}"), notice: "approval_saved", status: :see_other
  rescue StandardError
    redirect_to purchase_path("/"), alert: "approval_failed", status: :see_other
  end

  def show
    # Language changes read cached purchase summaries. Read-only health probes
    # may run, but never query purchase status, reconcile, approve, or execute.
    @purchase = if params[:refresh] == "1" && readiness.report.fetch("operations").fetch("status", false)
      safe_status(params[:id])
    else
      cached_history.find { |purchase| purchase["purchase_id"] == params[:id] }
    end
    return head :not_found unless @purchase
    index
  end

  def run_purchase
    PurchaseDemo::Runtime.authority.run(id: params[:id])
    redirect_to purchase_path("/purchases/#{params[:id]}"), status: :see_other
  rescue StandardError
    redirect_to purchase_path("/purchases/#{params[:id]}"), alert: "run_failed", status: :see_other
  end

  def recover
    PurchaseDemo::Runtime.authority.recover(id: params[:id])
    redirect_to purchase_path("/purchases/#{params[:id]}"), notice: "recovered", status: :see_other
  rescue StandardError
    redirect_to purchase_path("/purchases/#{params[:id]}"), alert: "recovery_failed", status: :see_other
  end

  private

  def readiness
    PurchaseDemo::Readiness.new(role: "authority")
  end

  def guard_operation!
    operation = {"approve" => "approve", "run_purchase" => "run", "recover" => "recover"}.fetch(action_name)
    return if readiness.report.fetch("operations").fetch(operation, false)
    render plain: purchase_text("flash.dependencies_unavailable"), status: :service_unavailable
  end

  # Only fixed diagnostic codes and public certificate times enter presentation.
  def readiness_display(report)
    statuses = %w[ready preparing unreachable certificate_update_required]
    translate_status = ->(value) { purchase_text("readiness.states.#{statuses.include?(value) ? value : 'unreachable'}") }
    services = [report] + report.fetch("dependencies", {}).values
    reasons = %w[rotation_pending expired expiring not_yet_valid ca_mismatch key_mismatch hostname_mismatch invalid_chain missing_tls_files invalid_tls_material tls_verification_failed tls_handshake_failed authentication_failed connection_failed]
    checks = %w[initialization maintenance files storage identity tls local_state]
    rows = %w[authority buyer seller].map do |role|
      service = services.find { |item| item["role"] == role } || {"status" => "unreachable"}
      codes = Array(service.dig("tls", "reasons")) + Array(service["reason"])
      details = codes.select { |code| reasons.include?(code) }.uniq.map { |code| purchase_text("readiness.reasons.#{code}") }
      Array(service["checks"]).each do |check|
        details << purchase_text("readiness.checks.#{check['name']}") if !check["ready"] && checks.include?(check["name"])
      end
      {"role" => role, "label" => purchase_text("readiness.roles.#{role}"), "status" => translate_status.call(service["local_status"] || service["status"]), "details" => details.uniq.join(" ")}
    end
    certificates = services.each_with_object({}) do |service, collected|
      value = service["certificates"]
      next unless value.is_a?(Hash)
      %w[ca buyer seller].each { |role| collected[role] = value[role] if value[role].is_a?(Hash) }
    end
    certificate_rows = %w[ca buyer seller].map do |role|
      cert = certificates[role] || {}
      expiry = cert["not_after"].is_a?(String) && cert["not_after"].match?(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/) ? cert["not_after"] : purchase_text("readiness.unknown")
      remaining = cert["remaining_seconds"].is_a?(Numeric) ? cert["remaining_seconds"].to_i : purchase_text("readiness.unknown")
      update = cert.empty? ? purchase_text("readiness.unknown") : purchase_text("readiness.#{cert['update_required'] ? 'renew' : 'valid'}")
      {"role" => role, "text" => purchase_text("readiness.certificate", role: purchase_text("readiness.roles.#{role}"), expiry: expiry, remaining: remaining, update: update)}
    end
    {"summary" => translate_status.call(report["status"]), "services" => rows, "certificates" => certificate_rows,
     "checked_at" => purchase_text("readiness.checked_at", time: report["checked_at"]),
     "operations" => report.fetch("operations", {}), "failure" => purchase_text("readiness.poll_failed"),
     "checking" => purchase_text("readiness.checking")}
  end

  def selected_locale
    candidate = params.key?(:locale) ? params[:locale] : session[:locale]
    %w[en ja].include?(candidate) ? candidate : "en"
  end

  def with_locale(&action)
    locale = selected_locale
    session[:locale] = locale
    I18n.with_locale(locale, &action)
  end

  def purchase_text(key, **values)
    I18n.t("purchase.#{key}", **values)
  end

  def purchase_path(path, locale: I18n.locale)
    "#{path}?#{Rack::Utils.build_query(locale: locale)}"
  end

  def language_path(locale)
    # Construct only a safe GET destination, never the current POST endpoint.
    path = @purchase ? "/purchases/#{@purchase.fetch('purchase_id')}" : "/"
    purchase_path(path, locale: locale)
  end

  def status_text(value)
    code = PurchaseDemo::SummaryCodes.status(value)
    code ? purchase_text("statuses.#{code}") : purchase_text("ui.unknown_status")
  end

  def reason_text(value)
    code = PurchaseDemo::SummaryCodes.reason(value)
    code ? purchase_text("reasons.#{code}") : purchase_text("ui.unknown_reason")
  end

  def flash_text(value)
    code = FLASH_CODES.include?(value) ? value : LEGACY_FLASH[value]
    purchase_text("flash.#{code || 'unknown'}")
  end

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
    # rescue_from runs outside the locale callback when CSRF verification raises.
    I18n.with_locale(selected_locale) do
      render plain: purchase_text("flash.expired_form"), status: :unprocessable_entity
    end
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
