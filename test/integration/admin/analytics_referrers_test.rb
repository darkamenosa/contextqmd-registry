# frozen_string_literal: true

require "test_helper"

class Admin::AnalyticsReferrersTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Ahoy::Event.delete_all
    Ahoy::Visit.delete_all
    Analytics::SiteBoundary.delete_all
    Analytics::Site.delete_all
    Analytics::Setting.delete_all
    Analytics::Goal.delete_all
  end

  test "google referrer alias requires gsc configuration" do
    staff_identity, = create_tenant(
      email: "staff-analytics-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Analytics"
    )
    staff_identity.update!(staff: true)
    site = Analytics::Bootstrap.ensure_default_site!(host: "localhost")

    sign_in(staff_identity)

    get "/admin/analytics/sites/#{site.public_id}/referrers",
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
