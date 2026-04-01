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

  test "24h uses a rolling 24 hour range" do
    travel_to Time.zone.parse("2026-03-28 10:35:00") do
      range, interval = Analytics::Ranges.range_and_interval_for("24h", nil, {})

      assert_equal "hour", interval
      assert_equal Time.zone.parse("2026-03-27 10:35:00"), range.begin
      assert_equal Time.zone.parse("2026-03-28 10:35:00"), range.end
    end
  end

  test "28d uses a four-week range" do
    travel_to Time.zone.parse("2026-03-28 10:00:00") do
      range, interval = Analytics::Ranges.range_and_interval_for("28d", nil, {})

      assert_equal "day", interval
      assert_equal Date.new(2026, 2, 28), range.begin.to_date
      assert_equal Date.new(2026, 3, 27), range.end.to_date
    end
  end

  test "91d uses a thirteen-week range" do
    travel_to Time.zone.parse("2026-03-28 10:00:00") do
      range, interval = Analytics::Ranges.range_and_interval_for("91d", nil, {})

      assert_equal "day", interval
      assert_equal Date.new(2025, 12, 27), range.begin.to_date
      assert_equal Date.new(2026, 3, 27), range.end.to_date
    end
  end

  test "previous_range preserves exact rolling durations" do
    range = Time.zone.parse("2026-03-27 10:35:00")..Time.zone.parse("2026-03-28 10:35:00")
    previous = Analytics::Ranges.previous_range(range, exact: true)

    assert_equal Time.zone.parse("2026-03-26 10:35:00"), previous.begin
    assert_equal Time.zone.parse("2026-03-27 10:35:00"), previous.end
  end

  test "24h previous period comparison can match exact time" do
    source_range = Time.zone.parse("2026-03-27 10:35:00")..Time.zone.parse("2026-03-28 10:35:00")
    comparison = Analytics::Ranges.comparison_range_for(
      { period: "24h", comparison: "previous_period", match_day_of_week: false },
      source_range
    )

    assert_equal Time.zone.parse("2026-03-26 10:35:00"), comparison.begin
    assert_equal Time.zone.parse("2026-03-27 10:35:00"), comparison.end
  end

  test "24h previous period comparison can match day of week" do
    source_range = Time.zone.parse("2026-03-27 10:35:00")..Time.zone.parse("2026-03-28 10:35:00")
    comparison = Analytics::Ranges.comparison_range_for(
      { period: "24h", comparison: "previous_period", match_day_of_week: true },
      source_range
    )

    assert_equal Time.zone.parse("2026-03-20 10:35:00"), comparison.begin
    assert_equal Time.zone.parse("2026-03-21 10:35:00"), comparison.end
  end
end
