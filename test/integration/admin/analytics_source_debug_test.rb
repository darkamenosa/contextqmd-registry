# frozen_string_literal: true

require "test_helper"

class Admin::AnalyticsSourceDebugTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Ahoy::Event.delete_all
    Ahoy::Visit.delete_all
    AnalyticsSetting.delete_all
    Goal.delete_all
    Funnel.delete_all
  end

  test "source debug shows normalized and raw source details for legacy aliases" do
    staff_identity, = create_tenant(
      email: "staff-source-debug-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Source Debug"
    )
    staff_identity.update!(staff: true)

    sign_in(staff_identity)

    Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      utm_source: "x",
      referring_domain: "x.com",
      started_at: Time.zone.now.change(usec: 0)
    )

    get "/admin/analytics/source_debug",
        params: { source: "x.com", period: "day" },
        headers: { "ACCEPT" => "application/json" }

    assert_response :success
    payload = JSON.parse(response.body)

    assert_equal "Twitter", payload.dig("source", "normalizedValue")
    assert_equal "social", payload.dig("source", "kind")
    assert_equal "x.com", payload.dig("source", "faviconDomain")
    assert_equal "utm-x", payload.fetch("matchedRules").first.fetch("value")
    assert_equal "x.com", payload.fetch("rawReferringDomains").first.fetch("value")
    assert_equal "x", payload.fetch("rawUtmSources").first.fetch("value")
  ensure
    Current.reset
  end
end
