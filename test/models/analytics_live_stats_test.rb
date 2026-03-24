# frozen_string_literal: true

require "test_helper"

class AnalyticsLiveStatsTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    Ahoy::Event.delete_all
    Ahoy::Visit.delete_all
  end

  test "yesterday session comparison excludes today's midnight boundary" do
    travel_to Time.utc(2026, 3, 24, 10, 0, 0) do
      Time.use_zone("UTC") do
        Ahoy::Visit.create!(
          visit_token: SecureRandom.hex(16),
          visitor_token: SecureRandom.hex(16),
          started_at: Time.zone.parse("2026-03-23 00:00:00")
        )
        Ahoy::Visit.create!(
          visit_token: SecureRandom.hex(16),
          visitor_token: SecureRandom.hex(16),
          started_at: Time.zone.parse("2026-03-24 00:00:00")
        )

        stats = AnalyticsLiveStats.build(now: Time.zone.parse("2026-03-24 10:00:00"), camelize: false)

        assert_equal 1, stats.dig(:today_sessions, :count)
        assert_equal 0, stats.dig(:today_sessions, :change)
      end
    end
  end
end
