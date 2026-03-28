# frozen_string_literal: true

require "test_helper"

class Analytics::OrderingTest < ActiveSupport::TestCase
  test "parsed_order_by normalizes metric names and directions" do
    assert_equal [ "bounce_rate", "asc" ],
      Analytics::Ordering.parsed_order_by([ [ "bounceRate", "asc" ] ])
  end

  test "parsed_order_by falls back to visitors for unsupported metrics" do
    assert_equal [ "visitors", "desc" ],
      Analytics::Ordering.parsed_order_by([ [ "unknownMetric", "sideways" ] ])
  end

  test "order_names sorts by derived metrics" do
    ordered = Analytics::Ordering.order_names(
      counts: { "Organic" => 12, "Direct" => 8, "Email" => 4 },
      metrics_map: {
        "Organic" => { bounce_rate: 30.0 },
        "Direct" => { bounce_rate: 12.0 },
        "Email" => { bounce_rate: 65.0 }
      },
      order_by: [ "bounce_rate", "asc" ]
    )

    assert_equal [ "Direct", "Organic", "Email" ], ordered
  end

  test "order_names_with_conversions sorts by conversion rate" do
    ordered = Analytics::Ordering.order_names_with_conversions(
      conversions: { "Organic" => 10, "Direct" => 8, "Email" => 6 },
      rates: { "Organic" => 4.2, "Direct" => 6.8, "Email" => 3.1 },
      order_by: [ "conversion_rate", "desc" ]
    )

    assert_equal [ "Direct", "Organic", "Email" ], ordered
  end
end
