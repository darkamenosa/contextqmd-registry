# frozen_string_literal: true

require "test_helper"

class Admin::AnalyticsSettingsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  INERTIA_HEADERS = {
    "X-Inertia" => "true",
    "X-Inertia-Version" => ViteRuby.digest,
    "X-Requested-With" => "XMLHttpRequest",
    "ACCEPT" => "text/html, application/xhtml+xml"
  }.freeze

  setup do
    Ahoy::Event.delete_all
    Ahoy::Visit.delete_all
    Analytics::AllowedEventProperty.delete_all if defined?(Analytics::AllowedEventProperty)
    Analytics::SiteTrackingRule.delete_all if defined?(Analytics::SiteTrackingRule)
    Analytics::Setting.delete_all
    Analytics::Goal.delete_all
    Analytics::Funnel.delete_all
    Analytics::SiteBoundary.delete_all
    Analytics::Site.delete_all
  end

  test "settings api persists goal definitions and allowed event props" do
    staff_identity, = create_tenant(
      email: "staff-analytics-settings-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Analytics Settings"
    )
    staff_identity.update!(staff: true)
    site = Analytics::Bootstrap.ensure_default_site!(host: "localhost")

    sign_in(staff_identity)

    patch settings_data_path_for(site),
      params: {
        settings: {
          goal_definitions: [
            {
              display_name: " Signup ",
              event_name: "signup",
              custom_props: { plan: "Pro" }
            },
            {
              display_name: "Visit Pricing",
              page_path: "pricing",
              scroll_threshold: -1,
              custom_props: {}
            }
          ],
          allowed_event_props: [ " plan ", "source", "" ],
          tracking_rules: {
            include_paths: [ "blog/**" ],
            exclude_paths: [ "/preview/**", "" ]
          }
        }
      },
      as: :json

    assert_response :no_content

    get settings_data_path_for(site), headers: { "ACCEPT" => "application/json" }

    assert_response :success

    payload = JSON.parse(response.body)
    settings = payload.fetch("settings")
    assert_equal false, settings.fetch("gscConfigured")
    assert_equal [ "Signup", "Visit Pricing" ], settings.fetch("goals")
    assert_equal 2, settings.fetch("goalDefinitions").length
    assert_equal [ "Signup", "Visit Pricing" ], Analytics::Goal.order(:display_name).pluck(:display_name)
    assert_equal [ "signup", nil ], Analytics::Goal.order(:display_name).pluck(:event_name)
    assert_equal [ nil, "/pricing" ], Analytics::Goal.order(:display_name).pluck(:page_path)
    assert_equal [ "plan", "source" ], settings.fetch("allowedEventProps")
    assert_equal [ "/blog/**" ], settings.fetch("trackingRules").fetch("includePaths")
    assert_equal [ "/preview/**" ], settings.fetch("trackingRules").fetch("excludePaths")
    assert_includes settings.fetch("trackingRules").fetch("effectiveExcludePaths"), "/analytics"
  ensure
    Current.reset
  end

  test "settings api allows multiple event goals with different property matches" do
    staff_identity, = create_tenant(
      email: "staff-analytics-settings-props-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Analytics Settings Props"
    )
    staff_identity.update!(staff: true)
    site = Analytics::Bootstrap.ensure_default_site!(host: "localhost")

    sign_in(staff_identity)

    patch settings_data_path_for(site),
      params: {
        settings: {
          goal_definitions: [
            {
              display_name: "Signup Pro",
              event_name: "signup",
              custom_props: { plan: "Pro" }
            },
            {
              display_name: "Signup Free",
              event_name: "signup",
              custom_props: { plan: "Free" }
            }
          ]
        }
      },
      as: :json

    assert_response :no_content
    assert_equal 2, Analytics::Goal.count
    assert_equal [ { "plan" => "Free" }, { "plan" => "Pro" } ], Analytics::Goal.order(:display_name).pluck(:custom_props)
  ensure
    Current.reset
  end

  test "site settings api persists isolated records per analytics site" do
    staff_identity, = create_tenant(
      email: "staff-analytics-settings-site-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Analytics Settings Site"
    )
    staff_identity.update!(staff: true)

    site_a = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    site_b = Analytics::Site.create!(name: "Blog", canonical_hostname: "blog.example.test")

    sign_in(staff_identity)

    patch "/admin/analytics/sites/#{site_a.public_id}/settings/data",
      params: {
        settings: {
          goal_definitions: [
            {
              display_name: "Docs Signup",
              event_name: "signup",
              custom_props: { plan: "Docs" }
            }
          ],
          allowed_event_props: [ "docs_plan" ]
        }
      },
      as: :json

    assert_response :no_content

    patch "/admin/analytics/sites/#{site_b.public_id}/settings/data",
      params: {
        settings: {
          goal_definitions: [
            {
              display_name: "Blog Signup",
              event_name: "signup",
              custom_props: { plan: "Blog" }
            }
          ],
          allowed_event_props: [ "blog_plan" ]
        }
      },
      as: :json

    assert_response :no_content

    get "/admin/analytics/sites/#{site_a.public_id}/settings/data", headers: { "ACCEPT" => "application/json" }

    assert_response :success

    payload = JSON.parse(response.body)
    settings = payload.fetch("settings")
    assert_equal [ "Docs Signup" ], settings.fetch("goals")
    assert_equal [ "docs_plan" ], settings.fetch("allowedEventProps")
    assert_equal [ site_a.id, site_b.id ], Analytics::Goal.order(:display_name).pluck(:analytics_site_id).sort
    assert_equal [ "docs_plan" ], Analytics::AllowedEventProperty.for_analytics_site(site_a).pluck(:property_name)
    assert_equal [ "blog_plan" ], Analytics::AllowedEventProperty.for_analytics_site(site_b).pluck(:property_name)
  ensure
    Current.reset
  end

  test "site settings api can clear all custom properties" do
    staff_identity, = create_tenant(
      email: "staff-analytics-settings-clear-props-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Analytics Settings Clear Props"
    )
    staff_identity.update!(staff: true)

    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    Analytics::AllowedEventProperty.sync_keys!(%w[plan cta], site: site)

    sign_in(staff_identity)

    patch "/admin/analytics/sites/#{site.public_id}/settings/data",
      params: {
        settings: {
          allowed_event_props: []
        }
      },
      as: :json

    assert_response :no_content
    assert_equal [], Analytics::AllowedEventProperty.for_analytics_site(site).pluck(:property_name)
  ensure
    Current.reset
  end

  test "settings api derives funnel page suggestions from tracked site pages" do
    staff_identity, = create_tenant(
      email: "staff-analytics-settings-funnel-suggestions-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Analytics Settings Funnel Suggestions"
    )
    staff_identity.update!(staff: true)
    site = Analytics::Bootstrap.ensure_default_site!(host: "localhost")

    visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      analytics_site: site,
      started_at: 5.minutes.ago.change(usec: 0),
      landing_page: "https://localhost/register"
    )

    2.times do
      Ahoy::Event.create!(
        visit: visit,
        analytics_site: site,
        name: "pageview",
        properties: { page: "/register?plan=pro" },
        time: 4.minutes.ago.change(usec: 0)
      )
    end

    Ahoy::Event.create!(
      visit: visit,
      analytics_site: site,
      name: "pageview",
      properties: { page: "/pricing" },
      time: 3.minutes.ago.change(usec: 0)
    )

    sign_in(staff_identity)

    get settings_data_path_for(site), headers: { "ACCEPT" => "application/json" }

    assert_response :success

    suggestions = JSON.parse(response.body)
      .fetch("settings")
      .fetch("funnelPageSuggestions")

    assert_equal "/register", suggestions.first.fetch("value")
    assert_equal "Register page", suggestions.first.fetch("label")
    assert_equal "equals", suggestions.first.fetch("match")
    assert_equal [ "/register", "/pricing" ], suggestions.map { |item| item.fetch("value") }
  ensure
    Current.reset
  end

  test "settings api exposes recent custom event goal suggestions" do
    staff_identity, = create_tenant(
      email: "staff-analytics-settings-goal-suggestions-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Analytics Settings Goal Suggestions"
    )
    staff_identity.update!(staff: true)
    site = Analytics::Bootstrap.ensure_default_site!(host: "localhost")

    visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      analytics_site: site,
      started_at: 10.minutes.ago.change(usec: 0),
      landing_page: "https://localhost/"
    )

    3.times do
      Ahoy::Event.create!(
        visit: visit,
        analytics_site: site,
        name: "signup",
        properties: { plan: "pro" },
        time: 9.minutes.ago.change(usec: 0)
      )
    end

    Ahoy::Event.create!(
      visit: visit,
      analytics_site: site,
      name: "purchase",
      properties: { amount: "49" },
      time: 8.minutes.ago.change(usec: 0)
    )

    Ahoy::Event.create!(
      visit: visit,
      analytics_site: site,
      name: "pageview",
      properties: { page: "/" },
      time: 7.minutes.ago.change(usec: 0)
    )

    Analytics::Goal.create!(
      analytics_site: site,
      display_name: "purchase",
      event_name: "purchase",
      custom_props: {}
    )

    sign_in(staff_identity)

    get settings_data_path_for(site), headers: { "ACCEPT" => "application/json" }

    assert_response :success

    suggestions = JSON.parse(response.body)
      .fetch("settings")
      .fetch("goalSuggestions")

    assert_equal [ "signup" ], suggestions.map { |item| item.fetch("name") }
    assert_equal 1, suggestions.first.fetch("recentVisits")
  ensure
    Current.reset
  end

  test "settings analytics page lists sites when no site is selected" do
    with_analytics_mode(:multi_site) do
      staff_identity, = create_tenant(
        email: "staff-analytics-settings-page-#{SecureRandom.hex(4)}@example.com",
        name: "Staff Analytics Settings Page"
      )
      staff_identity.update!(staff: true)

      site_a = Analytics::Site.create!(name: "Blog", canonical_hostname: "blog.example.test")
      site_b = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")

      sign_in(staff_identity)

      get "/admin/settings/analytics", headers: INERTIA_HEADERS

      assert_response :success

      payload = JSON.parse(response.body).fetch("props")
      assert_nil payload.fetch("site")
      assert_equal [ "Blog", "Docs" ], payload.fetch("sites").map { |site| site.fetch("name") }
      assert_equal "/admin/settings/analytics?site=#{site_a.public_id}", payload.fetch("sites").first.fetch("settingsPath")
      assert_equal "/admin/settings/analytics?site=#{site_b.public_id}", payload.fetch("sites").last.fetch("settingsPath")
    end
  ensure
    Current.reset
  end

  test "settings analytics page hides site selection when only one site exists" do
    staff_identity, = create_tenant(
      email: "staff-analytics-settings-single-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Analytics Settings Single"
    )
    staff_identity.update!(staff: true)

    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")

    sign_in(staff_identity)

    get "/admin/settings/analytics", headers: INERTIA_HEADERS

    assert_response :success

    payload = JSON.parse(response.body).fetch("props")
    assert_equal site.public_id, payload.fetch("site").fetch("id")
    assert_equal [], payload.fetch("sites")
    assert_equal "/admin/settings/analytics", payload.fetch("paths").fetch("settings")
    tracker = payload.fetch("settings").fetch("tracker")
    assert_equal "http://www.example.com/analytics/script.js", tracker.fetch("scriptUrl")
    assert_equal site.public_id, tracker.fetch("websiteId")
    assert_equal "docs.example.test", tracker.fetch("domainHint")
    assert_includes tracker.fetch("snippetHtml"), %(data-website-id="#{site.public_id}")
  ensure
    Current.reset
  end

  test "settings analytics page can resolve the site from a unique host in multi-site mode" do
    with_analytics_mode(:multi_site) do
      staff_identity, = create_tenant(
        email: "staff-analytics-settings-host-#{SecureRandom.hex(4)}@example.com",
        name: "Staff Analytics Settings Host"
      )
      staff_identity.update!(staff: true)

      site = Analytics::Site.create!(name: "Local", canonical_hostname: "localhost")
      Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")

      sign_in(staff_identity)
      host! "localhost"

      get "/admin/settings/analytics", headers: INERTIA_HEADERS

      assert_response :success

      payload = JSON.parse(response.body).fetch("props")
      assert_equal site.public_id, payload.fetch("site").fetch("id")
      assert_equal [ "Docs", "Local" ], payload.fetch("sites").map { |entry| entry.fetch("name") }
    end
  ensure
    host! "www.example.com"
    Current.reset
  end

  test "settings analytics page hides site selection in single-site mode even with extra active sites" do
    staff_identity, = create_tenant(
      email: "staff-analytics-settings-single-hidden-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Analytics Settings Single Hidden"
    )
    staff_identity.update!(staff: true)

    primary = Analytics::Bootstrap.ensure_default_site!(host: "localhost")
    Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    Analytics::Site.create!(name: "Blog", canonical_hostname: "blog.example.test")

    sign_in(staff_identity)

    get "/admin/settings/analytics", headers: INERTIA_HEADERS

    assert_response :success

    payload = JSON.parse(response.body).fetch("props")
    assert_equal primary.public_id, payload.fetch("site").fetch("id")
    assert_equal [], payload.fetch("sites")
  ensure
    Current.reset
  end

  test "settings analytics page exposes single-site bootstrap state when not initialized" do
    staff_identity, = create_tenant(
      email: "staff-analytics-settings-bootstrap-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Analytics Settings Bootstrap"
    )
    staff_identity.update!(staff: true)

    sign_in(staff_identity)
    host! "localhost"

    get "/admin/settings/analytics", headers: INERTIA_HEADERS

    assert_response :success

    payload = JSON.parse(response.body).fetch("props")
    initialization = payload.fetch("initialization")
    assert_nil payload.fetch("site")
    assert_equal true, initialization.fetch("singleSite")
    assert_equal false, initialization.fetch("initialized")
    assert_equal true, initialization.fetch("canBootstrap")
    assert_equal "/admin/settings/analytics/bootstrap", initialization.fetch("bootstrapPath")
    assert_equal "localhost", initialization.fetch("suggestedHost")
  ensure
    host! "www.example.com"
    Current.reset
  end

  test "bootstrap action initializes the default single-site analytics record" do
    staff_identity, = create_tenant(
      email: "staff-analytics-settings-bootstrap-action-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Analytics Settings Bootstrap Action"
    )
    staff_identity.update!(staff: true)

    sign_in(staff_identity)
    host! "localhost"

    assert_difference -> { Analytics::Site.active.count }, +1 do
      post "/admin/settings/analytics/bootstrap"
    end

    site = Analytics::Site.active.order(:id).first
    assert_equal "localhost", site.canonical_hostname
    assert_equal "localhost", site.name
    assert_redirected_to "/admin/settings/analytics"
  ensure
    host! "www.example.com"
    Current.reset
  end

  private
    def with_analytics_mode(mode)
      original_mode = Analytics.config.mode
      Analytics.config.mode = mode
      yield
    ensure
      Analytics.config.mode = original_mode
    end

    def settings_data_path_for(site)
      "/admin/analytics/sites/#{site.public_id}/settings/data"
    end
end
