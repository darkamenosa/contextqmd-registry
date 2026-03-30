# frozen_string_literal: true

class Analytics::LiveState
  LIVE_WINDOW = 5.minutes
  CACHE_KEY = "analytics:live:broadcast:scheduled".freeze
  COALESCE_WINDOW = 1.second
  SUBSCRIPTION_PURPOSE = "analytics-live-subscription".freeze

  class << self
    def build(now: Time.zone.now, camelize: true)
      payload = new(now:).build
      camelize ? payload.deep_transform_keys { |key| key.to_s.camelize(:lower) } : payload
    end

    def broadcast_later(site: ::Analytics::Current.site)
      site_key = site_public_id(site)
      Analytics::LiveBroadcastJob.perform_later(site_key) if should_enqueue_broadcast?(site_key:)
    rescue StandardError
      nil
    end

    def broadcast_now(now: Time.zone.now, site: ::Analytics::Current.site)
      resolved_site = resolve_site(site)
      resolved_boundary = resolved_site&.boundaries&.find_by(primary: true)

      ::Analytics::Current.set(site: resolved_site, site_boundary: resolved_boundary) do
        ActionCable.server.broadcast(
          broadcast_stream(site: resolved_site),
          build(now:, camelize: true)
        )
      end
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

    def broadcast_stream(site: ::Analytics::Current.site_or_default)
      site_key = site_public_id(site)
      site_key.present? ? "analytics:#{site_key}" : "analytics"
    end

    def subscription_token(site: ::Analytics::Current.site_or_default)
      subscription_verifier.generate(
        { "site_public_id" => site_public_id(site) },
        purpose: SUBSCRIPTION_PURPOSE,
        expires_in: 1.day
      )
    end

    def resolve_subscription_stream(token)
      return nil if token.blank?

      payload = subscription_verifier.verified(
        token,
        purpose: SUBSCRIPTION_PURPOSE
      )
      return nil unless payload.is_a?(Hash) && payload.key?("site_public_id")

      site_key = payload["site_public_id"]
      return nil if site_key != nil && !site_key.is_a?(String)

      broadcast_stream(site: site_key.presence)
    end

    private
      def should_enqueue_broadcast?(site_key:)
        if cache_available?
          Rails.cache.write(
            broadcast_cache_key(site_key),
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

      def broadcast_cache_key(site_key)
        [ CACHE_KEY, site_key.presence || "global" ].join(":")
      end

      def site_public_id(site)
        case site
        when Analytics::Site
          site.public_id
        else
          site.presence
        end
      end

      def resolve_site(site)
        case site
        when Analytics::Site, nil
          site
        else
          Analytics::Site.find_by(public_id: site.to_s)
        end
      end

      def subscription_verifier
        Rails.application.message_verifier(SUBSCRIPTION_PURPOSE)
      end
  end

  def initialize(now:, window: LIVE_WINDOW)
    @now = now
    @window = window
  end

  def build
    today_range = today
    yesterday_range = yesterday
    today_sessions_count = Ahoy::Visit.for_analytics_site.where(started_at: today_range).count
    yesterday_sessions_count = Ahoy::Visit.for_analytics_site.where(started_at: yesterday_range).count
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
        .for_analytics_site
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
