# frozen_string_literal: true

require "test_helper"

class AhoyVisitCountryFilterTest < ActiveSupport::TestCase
  setup do
    Ahoy::Visit.delete_all
  end

  test "normalizes visits to canonical country code and derived label" do
    visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      country: "United States",
      started_at: Time.zone.now.change(usec: 0)
    )

    assert_equal "US", visit.country_code
    assert_equal "United States", visit.country
  end

  test "country contains filter matches canonical country labels through country_code" do
    us_visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      country: "United States",
      started_at: Time.zone.now.change(usec: 0)
    )
    Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      country: "Germany",
      started_at: Time.zone.now.change(usec: 0)
    )

    filtered = Analytics::VisitScope.filtered({}, advanced_filters: [ [ "contains", "country", "united" ] ])

    assert_equal [ us_visit.id ], filtered.pluck(:id)
  end
end
