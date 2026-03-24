# frozen_string_literal: true

require "test_helper"

class Admin::AnalyticsReferrersTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Ahoy::Event.delete_all
    Ahoy::Visit.delete_all
    AnalyticsSetting.delete_all
  end

  test "google referrer alias requires gsc configuration" do
    staff_identity, = create_tenant(
      email: "staff-analytics-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Analytics"
    )
    staff_identity.update!(staff: true)

    sign_in(staff_identity)

    get "/admin/analytics/referrers",
        params: { source: "Google", period: "day" },
        headers: { "ACCEPT" => "application/json" }

    assert_response :unprocessable_entity
    assert_equal(
      { "errorCode" => "not_configured", "isAdmin" => true },
      JSON.parse(response.body)
    )
  ensure
    Current.reset
  end
end
