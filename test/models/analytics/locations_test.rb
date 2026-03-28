# frozen_string_literal: true

require "test_helper"

class Analytics::LocationsTest < ActiveSupport::TestCase
  test "location_label combines unique non-blank parts in city-first order" do
    assert_equal(
      "Barcelona, Catalonia, Spain",
      Analytics::Locations.location_label(
        city: "Barcelona",
        region: "Catalonia",
        country: "Spain"
      )
    )
  end

  test "location_label removes duplicate values and falls back when empty" do
    assert_equal(
      "Paris, France",
      Analytics::Locations.location_label(
        city: "Paris",
        region: "Paris",
        country: "France"
      )
    )

    assert_equal(
      "Visitor",
      Analytics::Locations.location_label(city: nil, region: nil, country: nil, fallback: "Visitor")
    )
  end
end
