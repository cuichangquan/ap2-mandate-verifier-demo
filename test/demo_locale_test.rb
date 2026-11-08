# frozen_string_literal: true
ENV["RAILS_ENV"] = "test"
require "minitest/autorun"
require "minitest/mock"
require "yaml"
require "uri"
require "nokogiri"
require_relative "../config/application"
require_relative "../app/services/merchant_scenario"
require "rack/mock"

class DemoLocaleTest < Minitest::Test
  class Browser
    def initialize
      @client = Rack::MockRequest.new(PurchaseDemo::Application)
      @cookies = {}
    end

    def get(path, **options)
      request(:get, path, **options)
    end

    def post(path, params)
      request(:post, path, params: params, "HTTP_ORIGIN" => "http://localhost")
    end

    def follow(response)
      raise "not a redirect" unless response.status == 303
      get(URI(response.headers.fetch("location")).request_uri)
    end

    private

    def request(method, path, **options)
      response = @client.public_send(method, path, { "HTTP_HOST" => "localhost",
        "HTTP_COOKIE" => @cookies.map { |key, value| "#{key}=#{value}" }.join("; ") }.merge(options))
      Array(response.headers["set-cookie"]).each do |cookie|
        key, value = cookie.split(";", 2).first.split("=", 2)
        @cookies[key] = value
      end
      response
    end
  end

  def setup
    Rails.cache.clear
    @browser = Browser.new
  end

  def document(response)
    Nokogiri::HTML(response.body)
  end

  def verify(scenario, locale: nil, browser: @browser)
    page = browser.get(locale ? "/?locale=#{locale}" : "/")
    token = document(page).at_css('input[name="authenticity_token"]')["value"]
    redirect = browser.post("/verify", { scenario: scenario, authenticity_token: token })
    assert_equal 303, redirect.status
    assert_equal "no-store", redirect.headers["cache-control"]
    browser.follow(redirect)
  end

  def switch(response, locale, browser: @browser)
    path = document(response).at_css(".languages a[lang='#{locale}']")["href"]
    refute_includes path, "run="
    browser.get(path)
  end

  def assert_locale(response, locale)
    assert_equal 200, response.status
    assert_equal locale, document(response).at_css("html")["lang"]
    assert_equal locale, document(response).at_css(".languages a[aria-current='page']")["lang"]
    refute_match(/translation missing|Translation missing/, response.body)
    if locale == "en"
      # The self-labelled language switch is the only Japanese text in English UI.
      doc = document(response)
      doc.css(".languages").remove
      refute_match(/[\p{Hiragana}\p{Katakana}\p{Han}]/, doc.text)
    end
  end

  def test_default_persistence_navigation_post_reload_and_invalid_locale
    assert_locale(@browser.get("/"), "en")
    assert_locale(@browser.get("/?locale=ja"), "ja")
    assert_locale(@browser.get("/merchant"), "ja")
    assert_locale(@browser.get("/multi-item"), "ja")
    result = verify("valid")
    assert_locale(result, "ja")
    assert_includes result.body, "検証成功"
    assert_locale(@browser.get("/"), "ja")
    %w[fr JA ../ja].each do |invalid|
      assert_locale(@browser.get("/?locale=#{invalid}"), "en")
      assert_locale(@browser.get("/"), "en")
    end
    assert_locale(@browser.get("/?locale[]=ja"), "en")
    assert_locale(@browser.get("/?locale[language]=ja"), "en")
  end

  def test_scenario_results_and_diagnostics_translate_without_reverification
    expected = { "valid" => "scoped_research_verified", "tampered" => "host_binding_mismatch",
      "expired" => "invalid_purchase_time", "missing_currency" => "invalid_host_context" }
    expected.each do |scenario, code|
      english = verify(scenario, locale: "en")
      assert_locale(english, "en")
      assert_includes english.body, code
      ScenarioVerifier.stub(:call, ->(*) { flunk "language switch or reload reverified" }) do
        japanese = switch(english, "ja")
        assert_locale(japanese, "ja")
        assert_includes japanese.body, code
        assert_equal document(english).css("#result code").map(&:text), document(japanese).css("#result code").map(&:text)
        assert_locale(@browser.get("/"), "ja")
        restored = switch(japanese, "en")
        assert_equal document(english).at_css("#result").text, document(restored).at_css("#result").text
        if scenario == "missing_currency"
          assert_includes english.body, "order.currency"
          assert_includes japanese.body, "必須項目"
          refute_equal document(english).at_css(".diagnostic-hint").text, document(japanese).at_css(".diagnostic-hint").text
        end
      end
    end
  end

  def test_unavailable_result_and_safe_error_messages_in_both_languages
    %w[en ja].each do |locale|
      File.stub(:binread, ->(*) { raise "private fixture content" }) do
        # Create the service outcome inside the stub; template loading remains normal.
        @unavailable = ScenarioVerifier.call("valid")
      end
      ScenarioVerifier.stub(:call, @unavailable) do
        result = verify("valid", locale: locale)
        assert_locale(result, locale)
        assert_includes result.body, "demo_verification_unavailable"
        refute_includes result.body, "private fixture content"
        assert_includes result.body, I18n.t("demo.result.reasons.unavailable", locale: locale)
      end
      page = @browser.get("/?locale=#{locale}")
      token = document(page).at_css('input[name="authenticity_token"]')["value"]
      invalid = @browser.post("/verify", { scenario: "unsupported", authenticity_token: token })
      assert_equal 400, invalid.status
      assert_includes invalid.body, I18n.t("demo.errors.invalid_scenario", locale: locale)
      csrf = @browser.post("/verify", { scenario: "valid", authenticity_token: "invalid" })
      assert_equal 422, csrf.status
      assert_includes csrf.body, I18n.t("demo.errors.expired_form", locale: locale)
    end
  end

  def test_merchant_switch_keeps_original_hash_and_receipt_outcomes
    english = @browser.get("/merchant?locale=en")
    assert_locale(english, "en")
    original = document(english).css("#merchant-scenario code").map(&:text)
    MerchantScenario.stub(:call, ->(*) { flunk "language switch or reload regenerated signatures" }) do
      japanese = switch(english, "ja")
      assert_locale(japanese, "ja")
      assert_equal original, document(japanese).css("#merchant-scenario code").map(&:text)
      assert_includes english.body, "Purchase success reported: No"
      assert_includes japanese.body, "購入成功通知: いいえ"
      assert_equal original, document(@browser.get("/merchant")).css("#merchant-scenario code").map(&:text)
    end
  end

  def test_multi_item_switch_preserves_quantities_amount_currency_and_results
    english = @browser.get("/multi-item?locale=en")
    assert_locale(english, "en")
    assert_includes english.body, "Coffee: 2 × 120 cents (USD)"
    assert_includes english.body, "Tea: 3 × 80 cents (USD)"
    assert_includes english.body, "Tea: 2 × 80 cents (USD)"
    MultiItemScenario.stub(:call, ->(*) { flunk "language switch or reload reran multi-item verification" }) do
      japanese = switch(english, "ja")
      assert_locale(japanese, "ja")
      assert_includes japanese.body, "コーヒー：2個 × 120 cents（USD）"
      assert_includes japanese.body, "お茶：3個 × 80 cents（USD）"
      ["480 cents", "400 cents", "scoped_research_verified", "constraint_mismatch", "Success", "Error"].each do |value|
        assert_includes english.body, value
        assert_includes japanese.body, value
      end
      assert_equal document(english).css("#multi-item-scenario code").map(&:text), document(japanese).css("#multi-item-scenario code").map(&:text)
      assert_locale(@browser.get("/multi-item"), "ja")
    end
  end

  def test_expired_or_evicted_snapshots_never_silently_run_again
    verification = verify("valid")
    merchant = @browser.get("/merchant")
    multi = @browser.get("/multi-item")
    Rails.cache.clear
    ScenarioVerifier.stub(:call, ->(*) { flunk "expired verification reran" }) do
      MerchantScenario.stub(:call, ->(*) { flunk "expired merchant reran" }) do
        MultiItemScenario.stub(:call, ->(*) { flunk "expired multi-item reran" }) do
          [verification, merchant, multi].each do |page|
            result = switch(page, "ja")
            assert_locale(result, "ja")
            assert_includes result.body, I18n.t("demo.snapshot_expired", locale: :ja)
            assert_nil document(result).at_css("#result, #merchant-scenario, #multi-item-scenario")
          end
        end
      end
    end
    # Only an explicit rerun creates new synthetic values after expiration.
    rerun = @browser.get("/merchant?locale=ja&run=1")
    assert_locale(rerun, "ja")
    refute_nil document(rerun).at_css("#merchant-scenario")
    assert_includes verify("valid").body, "scoped_research_verified"
  end

  def test_language_switch_with_lost_session_does_not_execute_crypto
    merchant = @browser.get("/merchant")
    multi = @browser.get("/multi-item")
    MerchantScenario.stub(:call, ->(*) { flunk "lost session regenerated merchant signatures" }) do
      MultiItemScenario.stub(:call, ->(*) { flunk "lost session reran multi-item verification" }) do
        [merchant, multi].each do |page|
          response = switch(page, "ja", browser: Browser.new)
          assert_locale(response, "ja")
          assert_includes response.body, I18n.t("demo.snapshot_expired", locale: :ja)
          assert_nil document(response).at_css("#merchant-scenario, #multi-item-scenario")
        end
      end
    end
  end

  def test_sessions_cannot_see_each_others_results_or_locale
    other = Browser.new
    first = verify("expired", locale: "ja")
    assert_locale(first, "ja")
    assert_locale(other.get("/"), "en")
    assert_nil document(other.get("/")).at_css("#result")
    second = verify("valid", browser: other)
    assert_locale(second, "en")
    assert_includes second.body, "scoped_research_verified"
    assert_includes @browser.get("/").body, "invalid_purchase_time"
    assert_equal :en, I18n.locale
  end

  def test_locale_is_scoped_even_when_the_action_raises
    MerchantScenario.stub(:call, ->(*) { raise "synthetic failure" }) do
      response = @browser.get("/merchant?locale=ja")
      assert_equal 500, response.status
      assert_equal :en, I18n.locale
    end
  end

  def test_translation_keys_and_interpolations_match_and_resolve
    files = %w[en ja].to_h do |locale|
      path = File.expand_path("../config/locales/demo.#{locale}.yml", __dir__)
      [locale, flatten(YAML.safe_load_file(path).fetch(locale).fetch("demo"))]
    end
    assert_equal files.fetch("en").keys.sort, files.fetch("ja").keys.sort
    files.fetch("en").each do |key, value|
      placeholders = value.scan(/%\{([^}]+)\}/).flatten.sort
      assert_equal placeholders, files.fetch("ja").fetch(key).scan(/%\{([^}]+)\}/).flatten.sort, key
      %w[en ja].each do |locale|
        rendered = I18n.t("demo.#{key}", locale: locale, raise: true, **placeholders.to_h { |name| [name.to_sym, "sample"] })
        assert_kind_of String, rendered
        refute_empty rendered
      end
    end
  end

  def flatten(hash, prefix = nil)
    hash.each_with_object({}) do |(key, value), result|
      path = [prefix, key].compact.join(".")
      value.is_a?(Hash) ? result.merge!(flatten(value, path)) : result[path] = value
    end
  end
end
