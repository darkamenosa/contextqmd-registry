# frozen_string_literal: true

class AnalyticsLiveStats
  LIVE_WINDOW = 5.minutes

  def self.build(now: Time.zone.now, camelize: true)
    stats = new(now).build
    camelize ? stats.deep_transform_keys { |key| key.to_s.camelize(:lower) } : stats
  end

  def initialize(now)
    @now = now
  end

  def build
    today_range = today
    yesterday_range = yesterday

    current_visitors = Ahoy::Visit.live_visitors_count

    today_sessions = Ahoy::Visit.where(started_at: today_range).count
    yesterday_sessions = Ahoy::Visit.where(started_at: yesterday_range).count

    buckets = 1.hour
    session_spark = Ahoy::Visit.sparkline_today_vs_yesterday(bucket: buckets, now: now, yesterday_full_day: true)

    {
      current_visitors: current_visitors,
      today_sessions: {
        count: today_sessions,
        change: pct_change(yesterday_sessions, today_sessions),
        sparkline: session_spark
      },
      sessions_by_location: sessions_by_location(today_range),
      visitor_dots: visitor_dots
    }
  end

  private

    attr_reader :now

    def today
      now.beginning_of_day..now
    end

    def yesterday
      (today.begin - 1.day)...today.begin
    end

    def sessions_by_location(range)
      Ahoy::Visit
        .where(started_at: range)
        .group(:country, :region, :city)
        .order(Arel.sql("COUNT(*) DESC"))
        .limit(5)
        .count
        .map do |(country, region, city), count|
          {
            country: country.to_s,
            region: region.to_s.presence,
            city: city.to_s.presence,
            country_code: country.to_s,
            visitors: count
          }
        end
    end

    def visitor_dots
      Ahoy::Visit.live_dots(limit: 200, window: LIVE_WINDOW, now: now)
    end

    def pct_change(previous, current)
      previous = previous.to_f
      current = current.to_f
      return 0 if previous <= 0

      (((current - previous) / previous) * 100).round
    end
end
