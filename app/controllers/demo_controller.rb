class DemoController < ActionController::Base
  def index
    response.headers["Cache-Control"] = "no-store"
    render :index
  end

  def merchant
    return head :not_found unless ENV["AP2_MERCHANT_CANDIDATE"] == "1"
    require_relative "../services/merchant_candidate"
    @merchant_candidate = MerchantCandidate.call
    response.headers["Cache-Control"] = "no-store"
    render :index
  end

  def verify
    response.headers["Cache-Control"] = "no-store"
    unless params[:scenario].is_a?(String) && ScenarioVerifier::LABELS.key?(params[:scenario])
      return head :bad_request
    end
    @scenario = params[:scenario]
    @outcome = ScenarioVerifier.call(@scenario)
    render :index
  end
end
