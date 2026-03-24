# frozen_string_literal: true

require "test_helper"

class Admin::AnalyticsLocationsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Ahoy::Event.delete_all
    Ahoy::Visit.delete_all
  end

  test "locations map endpoint returns country metadata" do
    staff_identity, = create_tenant(
      email: "staff-locations-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Locations"
    )
    staff_identity.update!(staff: true)

    Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      country: "US",
      started_at: Time.zone.now.change(usec: 0)
    )

    sign_in(staff_identity)

    get "/admin/analytics/locations",
        params: { period: "day", mode: "map", with_imported: "false" },
        headers: { "ACCEPT" => "application/json" }

    assert_response :success

    results = JSON.parse(response.body).dig("map", "results")
    assert_equal 1, results.length
    assert_equal "US", results.first.fetch("code")
    assert_equal "USA", results.first.fetch("alpha3")
    assert_equal "US", results.first.fetch("alpha2")
    assert_equal "United States", results.first.fetch("name")
  ensure
    Current.reset
  end
end
