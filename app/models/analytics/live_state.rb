# frozen_string_literal: true

class Analytics::LiveState
  LIVE_WINDOW = 5.minutes
  CACHE_KEY = "analytics:live:broadcast:scheduled".freeze
  SUBSCRIPTION_COUNT_CACHE_KEY = "analytics:live:subscription-count".freeze
  COALESCE_WINDOW = 1.second
  SUBSCRIPTION_PURPOSE = "analytics-live-subscription".freeze
  SUBSCRIPTION_TTL = 1.day

  class << self
    def build(now: Time.zone.now, camelize: true)
      payload = new(now:).build
      camelize ? payload.deep_transform_keys { |key| key.to_s.camelize(:lower) } : payload
    end

    def broadcast_later(site: ::Analytics::Current.site)
      site_key = site_public_id(site)
      return unless subscribers_present?(site_key:)

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

    def register_subscription(stream)
      subscription_id = SecureRandom.uuid
      adjust_subscription_count(stream, 1, subscription_id:)
      subscription_id
    end

    def unregister_subscription(stream, subscription_id:)
      adjust_subscription_count(stream, -1, subscription_id:)
    end

    private
      def subscribers_present?(site_key:)
        return true unless cache_available?

        Rails.cache.read(subscription_count_cache_key(site_key)).to_i.positive?
      rescue StandardError
        true
      end

      def should_enqueue_broadcast?(site_key:)
        return false unless cache_available?

        Rails.cache.write(
          broadcast_cache_key(site_key),
          true,
          expires_in: COALESCE_WINDOW,
          unless_exist: true
        )
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

      def subscription_count_cache_key(site_key)
        [ SUBSCRIPTION_COUNT_CACHE_KEY, site_key.presence || "global" ].join(":")
      end

      def adjust_subscription_count(stream, delta, subscription_id:)
        return if stream.blank? || !cache_available?
        return if subscription_id.blank?

        site_key =
          if stream == "analytics"
            nil
          elsif stream.start_with?("analytics:")
            stream.delete_prefix("analytics:")
          end

        key = subscription_count_cache_key(site_key)
        marker_key = subscription_marker_cache_key(site_key, subscription_id)

        if delta.positive?
          registered = Rails.cache.write(marker_key, true, expires_in: SUBSCRIPTION_TTL, unless_exist: true)
          return unless registered

          increment_subscription_count(key)
        else
          removed = Rails.cache.delete(marker_key)
          return unless removed

          decrement_subscription_count(key)
        end
      rescue StandardError
        nil
      end

      def increment_subscription_count(key)
        Rails.cache.write(key, 0, expires_in: SUBSCRIPTION_TTL, unless_exist: true)
        Rails.cache.increment(key, 1, expires_in: SUBSCRIPTION_TTL)
      end

      def decrement_subscription_count(key)
        count = Rails.cache.decrement(key, 1, expires_in: SUBSCRIPTION_TTL)

        if count.to_i <= 0
          Rails.cache.delete(key)
          0
        else
          count
        end
      end

      def subscription_marker_cache_key(site_key, subscription_id)
        [ SUBSCRIPTION_COUNT_CACHE_KEY, site_key.presence || "global", "subscription", subscription_id ].join(":")
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
    today_sessions_count = site_visit_total(today_range)
    yesterday_sessions_count = site_visit_total(yesterday_range)
    buckets = 1.hour

    {
      current_visitors: self.class.current_visitors(now:, window:),
      today_sessions: {
        count: today_sessions_count,
        change: pct_change(yesterday_sessions_count, today_sessions_count),
        sparkline: site_visit_sparkline(bucket: buckets)
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
      Analytics::FactStore.sessions_by_location(
        site: ::Analytics::Current.site_or_default,
        range: range,
        limit: 5
      ).map do |location|
        {
          country: Analytics::Country::Label.name_for(location.country_code).to_s.presence || "Unknown",
          region: location.region,
          city: location.city,
          country_code: Ahoy::Visit.normalize_country_code(location.country_code),
          visitors: location.visitors
        }
      end
    end

    def pct_change(previous, current)
      previous = previous.to_f
      current = current.to_f
      return 0 if previous <= 0

      (((current - previous) / previous) * 100).round
    end

    def site_visit_total(range)
      if site_visit_rollup_usable_for?(range)
        Analytics::SiteVisitHourlyRollup.sum_for(range:, site: ::Analytics::Current.site_or_default, column: :visits_count)
      else
        Analytics::FactStore.visit_relation(site: ::Analytics::Current.site_or_default, started_at_range: range).count
      end
    end

    def site_visit_sparkline(bucket:)
      if bucket == 1.hour && site_visit_rollup_usable_for?(today) && site_visit_rollup_usable_for?(yesterday)
        Analytics::SiteVisitHourlyRollup.sparkline_today_vs_yesterday(
          site: ::Analytics::Current.site_or_default,
          now: now,
          yesterday_full_day: true
        )
      else
        Analytics::Realtime.sparkline_today_vs_yesterday(
          bucket: bucket,
          now: now,
          yesterday_full_day: true
        )
      end
    end

    def site_visit_rollup_usable_for?(range)
      Analytics::SiteVisitHourlyRollup.usable_for?(range:, site: ::Analytics::Current.site_or_default)
    end
end
