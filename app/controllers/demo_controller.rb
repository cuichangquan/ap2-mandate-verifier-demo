class DemoController < ActionController::Base
  around_action :with_locale
  before_action :prevent_caching
  helper_method :locale_url, :demo_url, :diagnostic_for
  rescue_from ActionController::InvalidAuthenticityToken do
    with_locale do
      prevent_caching
      @input_error = "expired_form"
      render :index, status: :unprocessable_entity
    end
  end

  def index
    saved = read_snapshot(:verification)
    @scenario, @outcome = saved.values_at(:scenario, :outcome) if saved
    render :index
  end

  def merchant
    require_relative "../services/merchant_scenario"
    @merchant_scenario = presentation_snapshot(:merchant) { MerchantScenario.call }
    render :index
  end

  def multi_item
    return head :not_found unless MultiItemScenario.available?
    @multi_item_scenarios = presentation_snapshot(:multi_item) do
      [MultiItemScenario.call, MultiItemScenario.call(short_second: true)]
    end
    render :index
  end

  def verify
    unless params[:scenario].is_a?(String) && ScenarioVerifier::SCENARIOS.include?(params[:scenario])
      @input_error = "invalid_scenario"
      return render :index, status: :bad_request
    end
    write_snapshot(:verification, { scenario: params[:scenario], outcome: ScenarioVerifier.call(params[:scenario]) })
    # Refresh and language changes are now presentation-only GET requests.
    redirect_to demo_url(:index), status: :see_other
  end

  private

  def with_locale(&action)
    requested = params.key?(:locale) ? params[:locale] : session[:demo_locale]
    locale = requested.is_a?(String) && %w[en ja].include?(requested) ? requested : "en"
    session[:demo_locale] = locale
    I18n.with_locale(locale, &action)
  end

  def prevent_caching
    response.headers["Cache-Control"] = "no-store"
  end

  def demo_url(action, **options)
    url_for({ controller: "demo", action: action, locale: I18n.locale, only_path: true }.merge(options))
  end

  def locale_url(locale)
    demo_url(action_name == "verify" ? :index : action_name, locale: locale, view: "1")
  end

  def diagnostic_for(diagnostics)
    diagnostics && diagnostics.fetch(I18n.locale)
  end

  def snapshot_key(name)
    "demo_presentation_#{name}"
  end

  def read_snapshot(name)
    id = session[snapshot_key(name)]
    return unless id
    value = Rails.cache.read(["demo-presentation", name, id])
    @snapshot_expired = true unless value
    value
  end

  def write_snapshot(name, value)
    key = snapshot_key(name)
    previous_id = session[key]
    Rails.cache.delete(["demo-presentation", name, previous_id]) if previous_id
    id = SecureRandom.hex(24)
    Rails.cache.write(["demo-presentation", name, id], value, expires_in: 30 * 60)
    session[key] = id
    value
  end

  def presentation_snapshot(name)
    # An expired/evicted snapshot is never silently recomputed on language
    # switching or refresh. Only the explicit rerun link requests another run.
    if params[:view] == "1"
      value = read_snapshot(name)
      @snapshot_expired = true unless value
      value
    elsif !session[snapshot_key(name)] || params[:run] == "1"
      write_snapshot(name, yield)
    else
      read_snapshot(name)
    end
  end
end
