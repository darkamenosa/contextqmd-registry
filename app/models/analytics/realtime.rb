# frozen_string_literal: true

module Analytics::Realtime
  class << self
    def active_visits(now: Time.zone.now, window: 5.minutes)
      window_start = now - window

      Ahoy::Visit
        .for_analytics_site
        .where(started_at: window_start..now)
        .or(Ahoy::Visit.for_analytics_site.where(id: recent_event_visit_ids(window_start)))
        .distinct
    end

    def live_visitors_count(now: Time.zone.now, window: 5.minutes)
      cutoff = now - window
      recent_event_visitors = Ahoy::Visit.for_analytics_site.where(id: recent_event_visit_ids(cutoff))
        .distinct
        .count(:visitor_token)

      if recent_event_visitors.positive?
        recent_event_visitors
      else
        Ahoy::Visit.for_analytics_site.where(started_at: cutoff..now).distinct.count(:visitor_token)
      end
    end

    def active_visits_with_coordinates(window: 5.minutes, now: Time.zone.now)
      active_visits(now:, window:).merge(Ahoy::Visit.with_coordinates)
    end

    def live_dots(limit: 200, window: 5.minutes, now: Time.zone.now)
      window_start = now - window
      visits = active_visits_with_coordinates(window: window, now: now)
        .order(started_at: :desc)
        .limit(limit)

      event_times = Ahoy::Event
        .for_analytics_site
        .where(visit_id: visits.map(&:id))
        .where("time >= ?", window_start)
        .group(:visit_id)
        .maximum(:time)

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

    def sparkline_today_vs_yesterday(bucket: 15.minutes, now: Time.zone.now, yesterday_full_day: true, table: Ahoy::Visit.table_name, column: "started_at")
      start_today = now.beginning_of_day
      bucket_seconds = bucket.to_i
      bucket_count_today = (((now - start_today) / bucket).floor + 1).clamp(1, 24 * 60 * 60 / bucket_seconds)
      full_day_buckets = (24 * 60 * 60) / bucket_seconds
      bucket_count_yesterday = yesterday_full_day ? full_day_buckets : bucket_count_today

      today_series = series_counts(
        table: table,
        column: column,
        start_at: start_today,
        buckets: bucket_count_today,
        bucket_seconds: bucket_seconds
      )

      yesterday_series = series_counts(
        table: table,
        column: column,
        start_at: start_today - 1.day,
        buckets: bucket_count_yesterday,
        bucket_seconds: bucket_seconds
      )

      { today: today_series, yesterday: yesterday_series }
    end

    def series_counts(table:, column:, start_at:, buckets:, bucket_seconds:)
      finish = start_at + (buckets - 1) * bucket_seconds
      seconds = bucket_seconds.to_i
      seconds = 1 if seconds <= 0
      seconds = 86_400 if seconds > 86_400
      connection = Ahoy::Visit.connection
      start_ts = connection.quote("#{start_at.utc.strftime('%Y-%m-%d %H:%M:%S')}+00")
      finish_ts = connection.quote("#{finish.utc.strftime('%Y-%m-%d %H:%M:%S')}+00")
      table_name = connection.quote_table_name(table)
      column_name = connection.quote_column_name(column)
      sql = <<~SQL.squish
        WITH series AS (
          SELECT generate_series(
            TIMESTAMPTZ #{start_ts},
            TIMESTAMPTZ #{finish_ts},
            INTERVAL '#{seconds} seconds'
          ) AS bucket
        )
        SELECT
          s.bucket AS bucket,
          COUNT(t.id) AS value
        FROM series s
        LEFT JOIN #{table_name} t
          ON t.#{column_name} >= s.bucket
         AND t.#{column_name} < s.bucket + INTERVAL '#{seconds} seconds'
        GROUP BY s.bucket
        ORDER BY s.bucket ASC
      SQL

      rows = connection.exec_query(sql)
      rows.rows.map { |(_, value)| value.to_i }
    end

    def recent_event_visit_ids(window_start)
      Ahoy::Event.for_analytics_site.where("time >= ?", window_start).select(:visit_id).distinct
    end
  end
end
