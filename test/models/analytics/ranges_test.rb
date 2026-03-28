# frozen_string_literal: true

require "test_helper"

class Analytics::RangesTest < ActiveSupport::TestCase
  test "range_and_interval_for falls back for invalid custom dates" do
    travel_to Time.zone.parse("2026-03-28 10:00:00") do
      range, interval = Analytics::Ranges.range_and_interval_for("day", nil, { date: "not-a-date" })

      assert_equal "hour", interval
      assert_equal Date.new(2026, 3, 28), range.begin.to_date
      assert_equal Date.new(2026, 3, 28), range.end.to_date
    end
  end

  test "trim_range_to_now_if_applicable trims current day to the current hour" do
    travel_to Time.zone.parse("2026-03-28 10:35:00") do
      range, = Analytics::Ranges.range_and_interval_for("day", nil, {})
      trimmed = Analytics::Ranges.trim_range_to_now_if_applicable(range, "day")

      assert_equal range.begin, trimmed.begin
      assert_equal Time.zone.parse("2026-03-28 10:00:00").end_of_hour, trimmed.end
    end
  end
end
