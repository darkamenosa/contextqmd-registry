# frozen_string_literal: true

require Rails.root.join("lib/analytics/country")

class Analytics::LiveState
  LIVE_WINDOW = 5.minutes
  CACHE_KEY = "analytics:live:broadcast:scheduled".freeze
  COALESCE_WINDOW = 1.second

  class << self
    def build(now: Time.zone.now, camelize: true)
      payload = new(now:).build
      camelize ? payload.deep_transform_keys { |key| key.to_s.camelize(:lower) } : payload
    end

    def broadcast_later
      Analytics::LiveBroadcastJob.perform_later if should_enqueue_broadcast?
    rescue StandardError
      nil
    end

    def broadcast_now(now: Time.zone.now)
      ActionCable.server.broadcast("analytics", build(now:, camelize: true))
    end

    def current_visitors(now: Time.zone.now, window: LIVE_WINDOW)
      Analytics::Realtime.live_visitors_count(now:, window:)
    end

    def active_visits(now: Time.zone.now, window: LIVE_WINDOW)
      Analytics::Realtime.active_visits(now:, window:)
    end

    def active_visits_with_coordinates(now: Time.zone.now, window: LIVE_WINDOW)
      Analytics::Realtime.active_visits_with_coordinates(now:, window:)
    end

    private
      def should_enqueue_broadcast?
        if cache_available?
          Rails.cache.write(
            CACHE_KEY,
            true,
            unless_exist: true,
            expires_in: COALESCE_WINDOW
          )
        else
          false
        end
      rescue StandardError
        true
      end

      def cache_available?
        !Rails.cache.is_a?(ActiveSupport::Cache::NullStore)
      rescue StandardError
        true
      end
  end

  def initialize(now:, window: LIVE_WINDOW)
    @now = now
    @window = window
  end

  def build
    today_range = today
    yesterday_range = yesterday
    today_sessions_count = Ahoy::Visit.where(started_at: today_range).count
    yesterday_sessions_count = Ahoy::Visit.where(started_at: yesterday_range).count
    buckets = 1.hour

    {
      current_visitors: self.class.current_visitors(now:, window:),
      today_sessions: {
        count: today_sessions_count,
        change: pct_change(yesterday_sessions_count, today_sessions_count),
        sparkline: Analytics::Realtime.sparkline_today_vs_yesterday(
          bucket: buckets,
          now: now,
          yesterday_full_day: true
        )
      },
      sessions_by_location: sessions_by_location(today_range),
      visitor_dots: Analytics::Realtime.live_dots(limit: 200, window:, now:)
    }.merge(
      AnalyticsProfile::Live.payload(now:, window:)
    )
  end

  private
    attr_reader :now, :window

    def today
      now.beginning_of_day..now
    end

    def yesterday
      (today.begin - 1.day)...today.begin
    end

    def sessions_by_location(range)
      Ahoy::Visit
        .where(started_at: range)
        .group(:country_code, :region, :city)
        .order(Arel.sql("COUNT(*) DESC"))
        .limit(5)
        .count
        .map do |(country_code, region, city), count|
          {
            country: Analytics::Country::Label.name_for(country_code).to_s.presence || "Unknown",
            region: region.to_s.presence,
            city: city.to_s.presence,
            country_code: Ahoy::Visit.normalize_country_code(country_code),
            visitors: count
          }
        end
    end

    def pct_change(previous, current)
      previous = previous.to_f
      current = current.to_f
      return 0 if previous <= 0

      (((current - previous) / previous) * 100).round
    end
end
