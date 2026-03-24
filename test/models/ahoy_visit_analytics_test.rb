# frozen_string_literal: true

require "test_helper"

class AhoyVisitAnalyticsTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    Ahoy::Event.delete_all
    Ahoy::Visit.delete_all
    AnalyticsSetting.delete_all
    Funnel.delete_all
  end

  test "classifies facebook cpc traffic as paid social" do
    now = Time.zone.now.change(usec: 0)
    Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      utm_source: "facebook_ads",
      utm_medium: "cpc",
      started_at: now
    )

    payload = Ahoy::Visit.sources_payload(
      {
        period: "custom",
        from: now.to_date.iso8601,
        to: now.to_date.iso8601,
        filters: {},
        advanced_filters: {},
        mode: "channels"
      },
      limit: 10,
      page: 1
    )

    assert_equal [ "Paid Social" ], payload.fetch(:results).map { |row| row.fetch(:name) }
  end

  test "removed imported aggregates fall back to empty hashes" do
    range = Time.zone.now.beginning_of_day..Time.zone.now.end_of_day

    assert_equal({}, Ahoy::Visit.imported_pages_aggregates(range))
    assert_equal({}, Ahoy::Visit.imported_entry_aggregates(range))
    assert_equal({}, Ahoy::Visit.imported_exit_aggregates(range))
  end

  test "live visitors prefer recent event activity over recent started_at fallback" do
    now = Time.zone.now.change(usec: 0)

    active_by_event = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "visitor-event",
      started_at: now - 20.minutes,
      latitude: 21.0285,
      longitude: 105.8542
    )
    Ahoy::Event.create!(
      visit: active_by_event,
      name: "pageview",
      properties: { page: "/docs" },
      time: now - 2.minutes
    )

    Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "visitor-started",
      started_at: now - 2.minutes,
      latitude: 37.7749,
      longitude: -122.4194
    )

    assert_equal 1, Ahoy::Visit.live_visitors_count
  end

  test "live visitors fall back to recent started_at when there are no recent events" do
    now = Time.zone.now.change(usec: 0)

    Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "visitor-started",
      started_at: now - 2.minutes
    )

    assert_equal 1, Ahoy::Visit.live_visitors_count
  end

  test "recent with coordinates includes visits revived by recent events" do
    now = Time.zone.now.change(usec: 0)

    old_visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "visitor-event",
      started_at: now - 30.minutes,
      latitude: 21.0285,
      longitude: 105.8542
    )
    Ahoy::Event.create!(
      visit: old_visit,
      name: "pageview",
      properties: { page: "/docs" },
      time: now - 1.minute
    )

    ids = Ahoy::Visit.recent_with_coordinates(window: 5.minutes).pluck(:id)

    assert_includes ids, old_visit.id
  end

  test "custom comparison range covers the full compare_to day" do
    Time.use_zone("UTC") do
      range = Ahoy::Visit.custom_compare_range(
        compare_from: "2026-03-01",
        compare_to: "2026-03-07"
      )

      assert_equal Time.zone.parse("2026-03-01 00:00:00"), range.begin
      assert_equal Time.zone.parse("2026-03-07 23:59:59.999999999"), range.end
    end
  end

  test "invalid date params fall back instead of raising" do
    travel_to Time.utc(2026, 3, 24, 15, 30, 0) do
      Time.use_zone("UTC") do
        day_range, = Ahoy::Visit.range_and_interval_for("day", nil, { date: "not-a-date" })
        custom_range, = Ahoy::Visit.range_and_interval_for(
          "custom",
          nil,
          { from: "not-a-date", to: "still-not-a-date" }
        )

        assert_equal Time.zone.parse("2026-03-24 00:00:00"), day_range.begin
        assert_equal Time.zone.parse("2026-03-24 23:59:59.999999999"), day_range.end
        assert_equal Time.zone.parse("2026-03-17 00:00:00"), custom_range.begin
        assert_equal Time.zone.parse("2026-03-23 23:59:59.999999999"), custom_range.end
      end
    end
  end
end
