# frozen_string_literal: true
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require "cgi"
require "rack/mock"

# Separate Rack suite; no server, network, real signing key, or payment processor.
# The application reads the persistent session secret at boot, then this fixture
# directory is removed. Tests replace only the authority service entry point.
previous_state_dir = ENV["PURCHASE_STATE_DIR"]
previous_rails_env = ENV["RAILS_ENV"]
begin
  ENV["RAILS_ENV"] = "test"
  Dir.mktmpdir("purchase-ui-boot-") do |dir|
    ENV["PURCHASE_STATE_DIR"] = dir
    File.write(File.join(dir, "session_secret"), "synthetic-test-secret-" * 8)
    require_relative "../purchase_demo/authority_application"
  end
ensure
  previous_state_dir ? ENV["PURCHASE_STATE_DIR"] = previous_state_dir : ENV.delete("PURCHASE_STATE_DIR")
  previous_rails_env ? ENV["RAILS_ENV"] = previous_rails_env : ENV.delete("RAILS_ENV")
end

class PurchaseUITest < Minitest::Test
  class FakeAuthority
    attr_reader :records, :calls, :status_calls
    attr_accessor :lose_next_response
    def initialize
      @records, @calls, @status_calls = {}, [], []
    end
    def approve(id:, scenario:)
      @calls << [:approve, id, scenario]
      existing = @records[id]
      raise PurchaseDemo::BoundaryError if existing && existing["scenario"] != scenario
      @records[id] ||= {"purchase_id" => id, "scenario" => scenario,
        "approval" => {"item" => "お茶", "quantity" => 3, "max_amount" => 3000, "currency" => "JPY"},
        "offer" => {"quantity" => 3, "amount" => 2400}, "execution_count" => 0,
        "ap2_status" => "未実行", "app_status" => "承認済み", "payment_status" => "未開始", "receipt_status" => "未確認"}
      if lose_next_response
        self.lose_next_response = false
        raise IOError, "synthetic lost response"
      end
      id
    end
    def status(id:)
      @status_calls << id
      @records.fetch(id) { raise PurchaseDemo::BoundaryError }
    end
    def list = @records.values
    def run(id:)
      @calls << [:run, id]
      status(id: id)["execution_count"] = 1
    end
    def recover(id:)
      @calls << [:recover, id]
      status(id: id)
    end
  end

  class Browser
    attr_reader :cookie
    def initialize(app)
      @rack = Rack::MockRequest.new(app)
    end
    def request(method, path, params: nil, origin: nil, save_cookie: true)
      options = {"HTTP_HOST" => "localhost", "HTTP_COOKIE" => @cookie.to_s}
      options["HTTP_ORIGIN"] = origin if origin
      if params
        options["CONTENT_TYPE"] = "application/x-www-form-urlencoded"
        options[:input] = Rack::Utils.build_query(params)
      end
      response = @rack.request(method, "http://localhost#{path}", options)
      if save_cookie && response["set-cookie"]
        cookies = Array(response["set-cookie"]).flat_map { |v| v.split("\n") }
        @cookie = cookies.map { |v| v.split(";", 2).first }.join("; ")
      end
      response
    end
    def get(path) = request("GET", path)
    def post(path, params, **options) = request("POST", path, params: params, **options)
  end

  def setup
    @service = FakeAuthority.new
    @old_authority = PurchaseDemo::Runtime.method(:authority)
    service = @service
    PurchaseDemo::Runtime.define_singleton_method(:authority) { service }
    @browser = Browser.new(PurchaseDemo::AuthorityApplication)
    @home = @browser.get("/")
    @form = form(@home)
  end

  def teardown
    PurchaseDemo::Runtime.define_singleton_method(:authority, @old_authority)
  end

  def form(response)
    %w[authenticity_token draft_id].to_h do |name|
      value = response.body[/name="#{name}" value="([^"]+)"/, 1]
      [name, value && CGI.unescapeHTML(value)]
    end.merge("approved" => "1", "scenario" => "valid")
  end

  def approve(browser = @browser, values = @form)
    response = browser.post("/approve", values)
    assert_equal 303, response.status
    assert_equal "http://localhost/purchases/#{values.fetch('draft_id')}", response["location"]
    response
  end

  def test_home_displays_fixed_consent_and_four_distinct_stages
    assert_equal 200, @home.status
    ["お茶", "3,000", "AP2検証", "アプリの実行判断", "模擬決済の結果", "Receipt確認", "実課金なし"].each { |text| assert_includes @home.body, text }
    assert_match(/name="approved" value="1" required/, @home.body)
    refute_nil @form["draft_id"]
    refute_nil @form["authenticity_token"]
    assert_empty @service.calls
    assert_equal "no-store", @home["cache-control"]
    assert_equal "same-origin", @home["referrer-policy"]
    assert_includes @home["content-security-policy"], "default-src 'none'"
    assert_includes @home["content-security-policy"], "frame-ancestors 'none'"
    assert_includes @home["set-cookie"].to_s.downcase, "httponly"
    assert_includes @home["set-cookie"].to_s.downcase, "samesite=strict"
  end

  def test_requires_explicit_checkbox_valid_scenario_and_matching_draft
    [@form.reject { |k, _| k == "approved" }, @form.merge("approved" => "true"),
      @form.merge("scenario" => "external"), @form.merge("draft_id" => SecureRandom.uuid)].each do |values|
      response = @browser.post("/approve", values)
      assert_equal 303, response.status
      assert_equal "http://localhost/", response["location"]
    end
    assert_empty @service.calls
  end

  def test_missing_csrf_invalid_csrf_and_bad_origin_never_approve
    [@form.reject { |k, _| k == "authenticity_token" }, @form.merge("authenticity_token" => "invalid")].each do |values|
      assert_equal 422, @browser.post("/approve", values).status
    end
    assert_equal 422, @browser.post("/approve", @form, origin: "https://untrusted.example").status
    assert_empty @service.calls
  end

  def test_approval_does_not_execute_and_repeated_old_form_is_rejected
    approve
    assert_equal [[:approve, @form["draft_id"], "valid"]], @service.calls
    assert_equal 0, @service.records.fetch(@form["draft_id"])["execution_count"]
    repeated = @browser.post("/approve", @form)
    assert_equal "http://localhost/", repeated["location"]
    assert_equal 1, @service.calls.length
  end

  def test_lost_http_response_reuses_original_draft_and_purchase
    # Do not accept Set-Cookie: simulates losing the whole approval response.
    first = @browser.post("/approve", @form, save_cookie: false)
    assert_equal 303, first.status
    approve
    assert_equal [@form["draft_id"]], @service.records.keys
    assert_equal 2, @service.calls.count { |call| call.first == :approve }
  end

  def test_lost_service_response_keeps_ownership_and_same_draft_for_retry
    @service.lose_next_response = true
    response = @browser.post("/approve", @form)
    assert_equal "http://localhost/", response["location"]
    home = @browser.get("/")
    assert_equal @form["draft_id"], form(home)["draft_id"]
    assert_equal 200, @browser.get("/purchases/#{@form['draft_id']}").status
    approve(@browser, form(home))
    assert_equal 1, @service.records.length
  end

  def test_run_recover_and_repeated_runs_preserve_id
    approve
    path = "/purchases/#{@form['draft_id']}"
    token = form(@browser.get(path))["authenticity_token"]
    %w[run run recover].each do |action|
      response = @browser.post("#{path}/#{action}", {"authenticity_token" => token})
      assert_equal 303, response.status
      assert_equal "http://localhost#{path}", response["location"]
    end
    assert_equal [[:run, @form["draft_id"]], [:run, @form["draft_id"]], [:recover, @form["draft_id"]]], @service.calls.drop(1)
    assert_equal 1, @service.records.fetch(@form["draft_id"])["execution_count"]
    assert_equal 422, @browser.post("#{path}/run", {}).status
    assert_equal 422, @browser.post("#{path}/recover", {}).status
  end

  def test_other_browser_cannot_read_run_or_recover_owned_purchase
    approve
    other = Browser.new(PurchaseDemo::AuthorityApplication)
    other_home = other.get("/")
    refute_includes other_home.body, @form["draft_id"]
    path = "/purchases/#{@form['draft_id']}"
    assert_equal 404, other.get(path).status
    %w[run recover].each do |action|
      assert_equal 404, other.post("#{path}/#{action}", {"authenticity_token" => form(other_home)["authenticity_token"]}).status
    end
    assert_equal 1, @service.calls.length
  end

  def test_summary_allowlist_escapes_text_and_uses_owned_id_for_actions
    approve
    id = @form["draft_id"]
    @service.records.fetch(id).merge!("reason" => '<script>alert("test")</script>',
      "purchase_id" => "forged-service-id", "nonce" => "HIDDEN_NONCE",
      "private_key" => "HIDDEN_KEY", "wire" => "HIDDEN_WIRE",
      "offer" => {"quantity" => 3, "amount" => 2400, "nonce" => "HIDDEN_NESTED"})
    response = @browser.get("/purchases/#{id}")
    assert_equal 200, response.status
    assert_includes response.body, "&lt;script&gt;"
    refute_includes response.body, "<script>"
    %w[HIDDEN_NONCE HIDDEN_KEY HIDDEN_WIRE HIDDEN_NESTED forged-service-id].each { |secret| refute_includes response.body, secret }
    assert_includes response.body, "action=\"/purchases/#{id}/run\""
    assert_equal "no-store", response["cache-control"]
  end

  def test_history_uses_only_cached_owned_summaries_and_show_fetches_once
    approve
    first_id = @form.fetch("draft_id")
    second_form = form(@browser.get("/"))
    approve(@browser, second_form)
    second_id = second_form.fetch("draft_id")
    foreign_id = SecureRandom.uuid
    @service.approve(id: foreign_id, scenario: "valid")
    @service.records.fetch(first_id)["scenario"] = "<script>untrusted</script>"
    @service.records.fetch(first_id)["private_key"] = "HIDDEN_HISTORY_KEY"
    @service.status_calls.clear

    home = @browser.get("/")
    assert_equal 200, home.status
    assert_empty @service.status_calls
    assert_includes home.body, first_id
    assert_includes home.body, second_id
    refute_includes home.body, foreign_id
    refute_includes home.body, "HIDDEN_HISTORY_KEY"
    refute_includes home.body, "<script>"

    assert_equal 200, @browser.get("/purchases/#{second_id}").status
    assert_equal [second_id], @service.status_calls
  end

  def test_host_allowlist_rejects_untrusted_host
    response = Rack::MockRequest.new(PurchaseDemo::AuthorityApplication).get("http://untrusted.example/")
    assert_equal 403, response.status
  end
end
