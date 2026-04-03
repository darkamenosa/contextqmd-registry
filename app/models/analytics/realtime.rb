# frozen_string_literal: true

module Analytics::Realtime
  class << self
    def active_visits(now: Time.zone.now, window: 5.minutes)
      Analytics::FactStore.active_visits(site: current_site, now:, window:)
    end

    def live_visitors_count(now: Time.zone.now, window: 5.minutes)
      Analytics::FactStore.live_visitors_count(site: current_site, now:, window:)
    end

    def active_visits_with_coordinates(window: 5.minutes, now: Time.zone.now)
      Analytics::FactStore.active_visits(site: current_site, now:, window:, with_coordinates: true)
    end

    def live_dots(limit: 200, window: 5.minutes, now: Time.zone.now)
      window_start = now - window
      visits = active_visits_with_coordinates(window: window, now: now)
        .sort_by { |visit| [ visit.started_at || Time.at(0), visit.id.to_i ] }
        .reverse
        .first(limit)

      event_times = Analytics::FactStore.latest_event_times_by_visit_id(
        site: current_site,
        visit_ids: visits.map(&:id),
        since: window_start
      )

      visits.map do |visit|
        last_activity = event_times[visit.id] || visit.started_at || now
        city = visit.city.to_s.presence
        region = visit.region.to_s.presence
        country = visit.country.to_s.presence
        country_code = Ahoy::Visit.normalize_country_code(visit.try(:country_code))

        {
          lat: visit.latitude.to_f,
          lng: visit.longitude.to_f,
          label: Analytics::Locations.location_label(city:, region:, country:),
          city: city,
          region: region,
          country: country,
          country_code: country_code,
          type: "visitor",
          ts: (last_activity.to_f * 1000.0).to_i
        }
      end
    end

    def sparkline_today_vs_yesterday(bucket: 15.minutes, now: Time.zone.now, yesterday_full_day: true)
      start_today = now.beginning_of_day
      bucket_seconds = bucket.to_i
      bucket_count_today = (((now - start_today) / bucket).floor + 1).clamp(1, 24 * 60 * 60 / bucket_seconds)
      full_day_buckets = (24 * 60 * 60) / bucket_seconds
      bucket_count_yesterday = yesterday_full_day ? full_day_buckets : bucket_count_today

      today_series = Analytics::FactStore.visit_series_counts(
        site: current_site,
        start_at: start_today,
        buckets: bucket_count_today,
        bucket_seconds: bucket_seconds
      )

      yesterday_series = Analytics::FactStore.visit_series_counts(
        site: current_site,
        start_at: start_today - 1.day,
        buckets: bucket_count_yesterday,
        bucket_seconds: bucket_seconds
      )

      { today: today_series, yesterday: yesterday_series }
    end

    private
      def current_site
        ::Analytics::Current.site_or_default
      end
  end
end
