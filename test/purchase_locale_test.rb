# frozen_string_literal: true
require_relative "purchase_ui_test"
require "yaml"

# Reuses the existing ownership/CSRF/retry fixtures and security assertions.
# No network calls or mock payment side effects are needed to render translations.
class PurchaseLocaleTest < PurchaseUITest
  LOCALES = %w[en ja].freeze

  def translated(key, locale)
    I18n.t("purchase.#{key}", locale: locale, raise: true)
  end

  def assert_locale(response, locale)
    assert_equal 200, response.status
    assert_includes response.body, "<html lang=\"#{locale}\">"
    assert_includes response.body, translated("ui.approval_title", locale)
    refute_match(/translation missing|Translation missing/, response.body)
  end

  def language_link(response, locale)
    tag = response.body.scan(/<a\b[^>]*>/).find { |link| link.include?("hreflang=\"#{locale}\"") }
    refute_nil tag
    CGI.unescapeHTML(tag[/href="([^"]+)"/, 1])
  end

  def approved_page(locale = "en", scenario = "valid")
    home = @browser.get("/?locale=#{locale}")
    values = form(home).merge("scenario" => scenario)
    approval = approve(@browser, values)
    path = URI(approval["location"]).request_uri
    [values.fetch("draft_id"), @browser.get(path)]
  end

  def test_default_english_and_complete_home_in_both_languages
    assert_locale(@home, "en")
    LOCALES.each do |locale|
      home = @browser.get("/?locale=#{locale}")
      assert_locale(home, locale)
      %w[consent approve test_only language limitations privacy footer].each do |key|
        assert_includes home.body, CGI.escapeHTML(translated("ui.#{key}", locale))
      end
      PurchaseDemo::SCENARIOS.each do |scenario|
        assert_includes home.body, CGI.escapeHTML(translated("scenarios.#{scenario}", locale))
      end
      assert_equal locale, form(home).fetch("locale")
      assert_includes home.body, 'href="/?locale=en"'
      assert_includes home.body, 'href="/?locale=ja"'
      assert_includes home.body, "JPY"
    end
    # The only Japanese content allowed on the English home is the switch label.
    english = @browser.get("/?locale=en").body.gsub("日本語", "")
    refute_match(/[\p{Hiragana}\p{Katakana}\p{Han}]/, english)
    assert_empty @service.calls
  end

  def test_locale_survives_navigation_post_redirect_refresh_history_and_reload
    LOCALES.each do |locale|
      id, page = approved_page(locale)
      assert_locale(page, locale)
      assert_includes page.body, translated("flash.approval_saved", locale)
      assert_includes page.body, "href=\"/purchases/#{id}?locale=#{locale}\""
      %w[run recover].each do |action|
        response = @browser.post("/purchases/#{id}/#{action}", {
          "authenticity_token" => form(page).fetch("authenticity_token"), "locale" => locale})
        assert_equal 303, response.status
        assert_equal "http://localhost/purchases/#{id}?locale=#{locale}", response["location"]
        page = @browser.get(URI(response["location"]).request_uri)
        assert_locale(page, locale)
      end
      assert_locale(@browser.get("/purchases/#{id}?refresh=1"), locale)
      assert_locale(@browser.get("/purchases/#{id}"), locale)
      assert_locale(@browser.get("/"), locale)
      assert_equal 1, @service.records.fetch(id).fetch("execution_count")
    end
  end

  def test_language_switch_and_reload_never_call_status_approve_run_or_recover
    id, page = approved_page
    record = @service.records.fetch(id)
    record.merge!("payment_status" => "response_unknown", "receipt_status" => "unverified",
      "reason" => "response_timeout", "execution_count" => 1,
      "approval_original" => "ORIGINAL_SIGNED_APPROVAL", "receipt_jwt" => "ORIGINAL_SIGNED_RECEIPT")
    original = Marshal.dump(@service.records)
    calls = @service.calls.dup
    @service.status_calls.clear
    %w[ja en ja].each do |locale|
      path = language_link(page, locale)
      assert_equal "/purchases/#{id}?locale=#{locale}", path
      refute_match(/run|recover|approve|refresh/, path)
      page = @browser.get(path)
      assert_locale(page, locale)
      assert_locale(@browser.get(path), locale)
      assert_includes page.body, translated("statuses.response_unknown", locale)
      assert_includes page.body, translated("reasons.response_timeout", locale)
      refute_includes page.body, "ORIGINAL_SIGNED"
    end
    assert_equal original, Marshal.dump(@service.records)
    assert_equal calls, @service.calls
    assert_empty @service.status_calls
    assert_equal [id], @service.records.keys
    assert_equal 1, record.fetch("execution_count")
  end

  def test_invalid_locale_falls_back_to_english_even_after_japanese_and_cannot_run_actions
    id, = approved_page("ja")
    calls = @service.calls.dup
    @service.status_calls.clear
    %w[fr en-US JA ../ja].each do |locale|
      assert_locale(@browser.get("/purchases/#{id}?#{Rack::Utils.build_query(locale: locale)}"), "en")
    end
    assert_locale(@browser.get("/purchases/#{id}?locale[]=ja"), "en")
    assert_locale(@browser.get("/purchases/#{id}?locale[unsafe]=ja"), "en")
    assert_locale(@browser.get("/purchases/#{id}"), "en")
    assert_equal calls, @service.calls
    assert_empty @service.status_calls
  end

  def test_locale_does_not_leak_between_requests_browsers_or_threads
    original_locale = I18n.locale
    ja = Browser.new(PurchaseDemo::AuthorityApplication)
    en = Browser.new(PurchaseDemo::AuthorityApplication)
    assert_locale(ja.get("/?locale=ja"), "ja")
    assert_locale(en.get("/"), "en")
    assert_locale(ja.get("/"), "ja")
    assert_equal original_locale, I18n.locale
    # Separate sessions in parallel, with the request thread's locale restored.
    results = LOCALES.map do |locale|
      Thread.new do
        I18n.with_locale(locale == "en" ? :ja : :en) do
          previous = I18n.locale
          browser = Browser.new(PurchaseDemo::AuthorityApplication)
          response = browser.get("/?locale=#{locale}")
          [locale, response, previous, I18n.locale]
        end
      end
    end.map(&:value)
    results.each do |locale, response, previous, after|
      assert_locale(response, locale)
      assert_equal previous, after
    end
    assert_equal original_locale, I18n.locale
  end

  def test_all_result_codes_and_legacy_japanese_render_without_mutating_records
    id, = approved_page
    record = @service.records.fetch(id)
    codes = PurchaseDemo::SummaryCodes
    LOCALES.each do |locale|
      codes::STATUS_CODES.each do |code|
        codes::STATUS_FIELDS.each { |field| record[field] = code }
        before = Marshal.dump(record)
        response = @browser.get("/purchases/#{id}?locale=#{locale}")
        assert_locale(response, locale)
        assert_includes response.body, CGI.escapeHTML(translated("statuses.#{code}", locale))
        assert_equal before, Marshal.dump(record)
      end
      codes::LEGACY_STATUSES.each do |legacy, code|
        codes::STATUS_FIELDS.each { |field| record[field] = legacy }
        before = Marshal.dump(record)
        response = @browser.get("/purchases/#{id}?locale=#{locale}")
        assert_includes response.body, CGI.escapeHTML(translated("statuses.#{code}", locale))
        assert_equal before, Marshal.dump(record)
      end
      (codes::REASON_CODES.to_h { |code| [code, code] }.merge(codes::LEGACY_REASONS)).each do |value, code|
        record["reason"] = value
        before = Marshal.dump(record)
        response = @browser.get("/purchases/#{id}?locale=#{locale}")
        assert_includes response.body, CGI.escapeHTML(translated("reasons.#{code}", locale))
        assert_equal before, Marshal.dump(record)
      end
    end
  end

  def test_each_scenario_result_and_history_has_translated_explanation
    states = {
      "valid" => %w[verified accepted_no_retry mock_success_verified receipt_success purchase_complete],
      "budget" => %w[issuance_refused not_accepted not_started unverified payment_refused],
      "quantity" => %w[issuance_refused not_accepted not_started unverified checkout_refused],
      "tampered" => %w[rejected not_accepted not_started unverified ap2_rejected],
      "error" => %w[verified accepted_no_retry mock_error_verified receipt_error payment_failed],
      "timeout" => %w[verified accepted_no_retry response_unknown unverified response_timeout],
      "wrong_receipt" => %w[verified accepted_no_retry unconfirmed_no_retry receipt_rejected receipt_rejected],
      "invalid_receipt" => %w[verified accepted_no_retry unconfirmed_no_retry receipt_rejected receipt_rejected]
    }
    states.each do |scenario, values|
      id, = approved_page("en", scenario)
      record = @service.records.fetch(id)
      record.merge!(%w[ap2_status app_status payment_status receipt_status reason].zip(values).to_h)
      LOCALES.each do |locale|
        response = @browser.get("/purchases/#{id}?locale=#{locale}")
        assert_locale(response, locale)
        assert_includes response.body, translated("scenarios.#{scenario}", locale)
        assert_includes response.body, translated("reasons.#{values.last}", locale)
        assert_includes response.body, translated("ui.history", locale)
      end
    end
  end

  def test_unknown_legacy_text_is_not_treated_as_success_or_exposed
    id, = approved_page
    @service.records.fetch(id).merge!("payment_status" => "古い不明な状態",
      "reason" => '<script>SECRET_NONCE</script>')
    LOCALES.each do |locale|
      response = @browser.get("/purchases/#{id}?locale=#{locale}")
      assert_includes response.body, translated("ui.unknown_status", locale)
      assert_includes response.body, translated("ui.unknown_reason", locale)
      refute_includes response.body, "SECRET_NONCE"
      refute_includes response.body, "古い不明な状態"
      refute_includes response.body, translated("statuses.mock_success_verified", locale)
    end
  end

  def test_translated_validation_csrf_and_service_errors_preserve_guards
    LOCALES.each do |locale|
      home = @browser.get("/?locale=#{locale}")
      values = form(home)
      denied = @browser.post("/approve", values.reject { |key, _| key == "approved" })
      assert_equal 303, denied.status
      assert_empty @service.calls
      assert_includes @browser.get(URI(denied["location"]).request_uri).body, translated("flash.approval_required", locale)
      invalid = @browser.post("/approve", values.merge("authenticity_token" => "invalid"))
      assert_equal 422, invalid.status
      assert_equal translated("flash.expired_form", locale), invalid.body
      assert_empty @service.calls
      assert_equal :en, I18n.locale
    end
    %w[approval_failed run_failed recovery_failed].each do |error|
      LOCALES.each do |locale|
        home = @browser.get("/?locale=#{locale}")
        if error == "approval_failed"
          @service.lose_next_response = true
          failed = @browser.post("/approve", form(home))
        else
          id, page = approved_page(locale)
          action = error == "run_failed" ? "run" : "recover"
          @service.define_singleton_method(action) { |id:| raise IOError, "PRIVATE_ERROR" }
          failed = @browser.post("/purchases/#{id}/#{action}", {
            "authenticity_token" => form(page).fetch("authenticity_token"), "locale" => locale})
        end
        assert_equal 303, failed.status
        page = @browser.get(URI(failed["location"]).request_uri)
        assert_includes page.body, translated("flash.#{error}", locale)
        refute_includes page.body, "PRIVATE_ERROR"
      end
    end
  end

  def test_no_locale_can_bypass_ownership_or_csrf
    id, = approved_page
    foreign = Browser.new(PurchaseDemo::AuthorityApplication)
    LOCALES.each do |locale|
      home = foreign.get("/?locale=#{locale}")
      assert_equal 404, foreign.get("/purchases/#{id}?locale=#{locale}").status
      assert_equal 404, foreign.get("/purchases/#{id}?locale=#{locale}&refresh=1").status
      %w[run recover].each do |action|
        assert_equal 404, foreign.post("/purchases/#{id}/#{action}", {
          "authenticity_token" => form(home).fetch("authenticity_token"), "locale" => locale}).status
        assert_equal 422, @browser.post("/purchases/#{id}/#{action}", {"locale" => locale}).status
        assert_raises(ActionController::RoutingError) do
          @browser.get("/purchases/#{id}/#{action}?locale=#{locale}")
        end
      end
    end
    assert_equal [[:approve, id, "valid"]], @service.calls
    assert_equal 0, @service.records.fetch(id).fetch("execution_count")
  end

  def test_pending_cookie_flash_is_localized_consumed_once_and_never_changes_purchases
    id, = approved_page
    original_records = Marshal.dump(@service.records)
    original_calls = @service.calls.dup
    @service.status_calls.clear
    current = PurchaseAuthorityController::FLASH_CODES.to_h { |code| [code, code] }
    legacy = {
      "商品・数量・上限金額を確認して承認してください。" => "approval_required",
      "この条件で購入を承認しました。実行はまだ開始していません。" => "approval_saved",
      "承認を保存できませんでした。状態を確認してから再度お試しください。" => "approval_failed",
      "実行結果を確認できませんでした。再実行前に状態を更新してください。" => "run_failed",
      "保存済みの結果を照会しました。各段階の状態をご確認ください。" => "recovered",
      "復旧照会を完了できませんでした。購入IDを維持して再度確認してください。" => "recovery_failed"
    }
    unknown = {"不明な過去のメッセージ" => "unknown", '<script>PRIVATE_FLASH_VALUE</script>' => "unknown",
      "missing.flash.key" => "unknown"}
    LOCALES.each do |locale|
      current.merge(legacy).merge(unknown).each do |value, code|
        # Seed one pending flash through Rails' actual encrypted CookieStore.
        # The subsequent request receives only that cookie, never an injected
        # flash hash, matching an old cookie surviving an application upgrade.
        seed_pending_flash = true
        app = lambda do |env|
          if seed_pending_flash
            env["action_dispatch.request.flash_hash"] = ActionDispatch::Flash::FlashHash.new(
              "notice" => value, "alert" => value)
            seed_pending_flash = false
          end
          PurchaseDemo::AuthorityApplication.call(env)
        end
        browser = Browser.new(app)
        browser.instance_variable_set(:@cookie, @browser.cookie)
        seeded = browser.get("/purchases/#{id}")
        assert_equal 200, seeded.status
        refute_nil seeded["set-cookie"]
        response = browser.get("/purchases/#{id}?locale=#{locale}")
        assert_locale(response, locale)
        expected = CGI.escapeHTML(translated("flash.#{code}", locale))
        assert_includes response.body, %(<div class="notice" role="status">#{expected}</div>)
        assert_includes response.body, %(<div class="notice alert" role="alert">#{expected}</div>)
        refute_includes response.body, CGI.escapeHTML(value) if locale == "en" || unknown.key?(value) || current.key?(value)
        refute_match(/translation missing/i, response.body)
        refute_includes response.body, "PRIVATE_FLASH_VALUE"
        consumed = browser.get("/purchases/#{id}?locale=#{locale}")
        refute_match(/<div class="notice(?: alert)?" role="(?:status|alert)">/, consumed.body)
        assert_equal original_records, Marshal.dump(@service.records)
        assert_equal original_calls, @service.calls
        assert_empty @service.status_calls
      end
    end
  end

  def test_mobile_markup_keeps_headline_and_history_text_separate
    LOCALES.each do |locale|
      id, page = approved_page(locale)
      headline = page.body[/<h1>(.*?)<\/h1>/m, 1]
      assert_includes headline, "<br> "
      assert_equal "#{translated('ui.headline_first', locale)} #{translated('ui.headline_second', locale)}",
        CGI.unescapeHTML(headline.gsub("<br>", ""))
      assert_match(/@media\(max-width:800px\).*?\.history li>span\{display:block\}/m, page.body)
      assert_match(%r{<li><a[^>]+>#{Regexp.escape(id)}</a><span>}, page.body)
    end
  end

  def test_translation_catalogs_have_identical_nonempty_keys_and_interpolations
    flatten = lambda do |value, path = [], result = {}|
      value.each do |key, child|
        child.is_a?(Hash) ? flatten.call(child, path + [key], result) : result[(path + [key]).join(".")] = child
      end
      result
    end
    dictionaries = LOCALES.to_h do |locale|
      data = YAML.safe_load_file(File.expand_path("../purchase_demo/locales/#{locale}.yml", __dir__))
      [locale, flatten.call(data.fetch(locale).fetch("purchase"))]
    end
    assert_equal dictionaries.fetch("en").keys.sort, dictionaries.fetch("ja").keys.sort
    dictionaries.fetch("en").each do |key, english|
      japanese = dictionaries.fetch("ja").fetch(key)
      assert_kind_of String, english
      assert_kind_of String, japanese
      refute_empty english
      refute_empty japanese
      assert_equal english.scan(/%\{(\w+)\}/).sort, japanese.scan(/%\{(\w+)\}/).sort, key
    end
  end
end
