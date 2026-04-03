# frozen_string_literal: true

class Analytics::SiteVisitHourlyRollup < AnalyticsRecord
  self.table_name = "analytics_site_visit_hourly_rollups"

  COALESCE_WINDOW = 1.second
  include Analytics::CoalescedRollupRefresh
  extend Analytics::HourlyBucketRange

  belongs_to :analytics_site, class_name: "Analytics::Site"

  scope :for_analytics_site, ->(site = ::Analytics::Current.site_or_default) { Analytics::Scope.apply(all, site:) }

  class << self
    def available?
      connection.data_source_exists?(table_name)
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
      false
    end

    def refresh_bucket!(site:, bucket_start:)
      return unless available?

      site_id = normalize_site_id(site)
      bucket = bucket_start_for(bucket_start)
      return if site_id.blank? || bucket.blank?

      totals = Analytics::FactStore.visit_totals_for_bucket(site: site_id, bucket_start: bucket)
      visits_count = totals.fetch(:visits_count, 0).to_i
      unique_visitors_count = totals.fetch(:unique_visitors_count, 0).to_i
      pageviews_count, bounces_count, total_visit_duration_seconds = visit_metric_totals_for_bucket(site: site_id, visit_ids: totals.fetch(:visit_ids, []))

      now = Time.current
      upsert(
        {
          analytics_site_id: site_id,
          bucket_start: bucket,
          visits_count: visits_count,
          unique_visitors_count: unique_visitors_count,
          pageviews_count: pageviews_count,
          bounces_count: bounces_count,
          total_visit_duration_seconds: total_visit_duration_seconds,
          created_at: now,
          updated_at: now
        },
        unique_by: :idx_site_visit_hourly_rollups_on_site_bucket
      )
    end

    def refresh_range!(site:, range:)
      return unless available?

      each_bucket(range) { |bucket_start| refresh_bucket!(site:, bucket_start:) }
    end

    def usable_for?(range:, site:)
      return false unless available?

      expected_bucket_count = expected_full_bucket_count(range:)
      return true if expected_bucket_count.zero?

      coverage_relation = scoped_full_buckets(range:, site:)
      coverage_relation.distinct.count(:bucket_start) == expected_bucket_count
    rescue StandardError
      false
    end

    def sum_for(range:, site:, column: :visits_count)
      return 0 unless available?

      rollup_total = scoped_full_buckets(range:, site:).sum(column)
      edge_total = edge_ranges_for(range).sum { |edge_range| raw_total_for_range(site:, range: edge_range, column:) }

      coerce_numeric(rollup_total) + coerce_numeric(edge_total)
    end

    def series_for(range:, interval:, site:, column: :visits_count)
      return {} unless available?

      grouped = scoped_full_buckets(range:, site:)
        .group(Arel.sql(Analytics::Ranges.bucket_sql_for("bucket_start", interval)))
        .sum(column)

      result = grouped.each_with_object({}) do |(bucket_time, value), series|
        series[normalize_bucket_time(bucket_time)] = value.to_i
      end

      raw_series_for_edges(range:, interval:, site:, column:).each do |bucket_time, value|
        normalized_bucket_time = normalize_bucket_time(bucket_time)
        result[normalized_bucket_time] = result.fetch(normalized_bucket_time, 0) + value.to_i
      end

      result
    end

    def complex_metrics_usable_for?(range:, site:)
      return false unless available?
      return false unless column_names.include?("pageviews_count")
      return false unless full_hour_aligned_range?(range)

      expected_bucket_count = expected_full_bucket_count(range:)
      return true if expected_bucket_count.zero?

      scope = scoped_full_buckets(range:, site:)
      scope.distinct.count(:bucket_start) == expected_bucket_count &&
        !scope.where("pageviews_count IS NULL OR bounces_count IS NULL OR total_visit_duration_seconds IS NULL").exists?
    rescue StandardError
      false
    end

    def complex_metric_series(range:, interval:, site:, metric:)
      return {} unless complex_metrics_usable_for?(range:, site:)

      grouped = scoped_full_buckets(range:, site:)
        .group(Arel.sql(Analytics::Ranges.bucket_sql_for("bucket_start", interval)))
        .pluck(
          Arel.sql(Analytics::Ranges.bucket_sql_for("bucket_start", interval)),
          Arel.sql("COALESCE(SUM(visits_count), 0)"),
          Arel.sql("COALESCE(SUM(pageviews_count), 0)"),
          Arel.sql("COALESCE(SUM(bounces_count), 0)"),
          Arel.sql("COALESCE(SUM(total_visit_duration_seconds), 0)")
        )

      grouped.each_with_object({}) do |(bucket_time, visits_count, pageviews_count, bounces_count, total_duration), result|
        key = normalize_bucket_time(bucket_time)
        denominator = visits_count.to_i

        result[key] =
          case metric.to_s
          when "views_per_visit"
            denominator.positive? ? (pageviews_count.to_f / denominator.to_f).round(2) : 0.0
          when "bounce_rate"
            denominator.positive? ? ((bounces_count.to_f / denominator.to_f) * 100.0).round(2) : 0.0
          when "visit_duration"
            denominator.positive? ? (total_duration.to_f / denominator.to_f).round(1) : 0.0
          else
            0.0
          end
      end
    end

    def sparkline_today_vs_yesterday(site:, now: Time.zone.now, yesterday_full_day: true)
      start_today = now.beginning_of_day
      bucket_count_today = ((now.hour) + 1).clamp(1, 24)
      bucket_count_yesterday = yesterday_full_day ? 24 : bucket_count_today

      {
        today: bucket_counts(start_at: start_today, buckets: bucket_count_today, site:),
        yesterday: bucket_counts(start_at: start_today - 1.day, buckets: bucket_count_yesterday, site:)
      }
    end

    private
      def bucket_counts(start_at:, buckets:, site:)
        range = start_at..(start_at + (buckets - 1).hours)
        counts = scoped_range(range:, site:).pluck(:bucket_start, :visits_count).each_with_object({}) do |(bucket_start, value), result|
          result[normalize_bucket_time(bucket_start)] = value.to_i
        end

        Array.new(buckets) do |index|
          counts[(start_at + index.hours).utc] || 0
        end
      end

      def scoped_range(range:, site:)
        site_id = normalize_site_id(site)
        window = bucket_window_for(range)
        return none if site_id.blank? || window.blank?

        where(analytics_site_id: site_id, bucket_start: window)
      end

      def scoped_full_buckets(range:, site:)
        site_id = normalize_site_id(site)
        window = interior_bucket_window_for(range)
        return none if site_id.blank? || window.blank?

        where(analytics_site_id: site_id, bucket_start: window)
      end

      def visit_metric_totals_for_bucket(site:, visit_ids:)
        if Analytics::VisitSummary.usable_for_visit_ids?(visit_ids)
          summary_metric_totals_for_visit_ids(visit_ids)
        else
          Analytics::FactStore.raw_visit_metric_totals(site:, visit_ids:)
        end
      end

      def summary_metric_totals_for_visit_ids(visit_ids)
        summaries = Analytics::VisitSummary.where(visit_id: visit_ids)

        [
          summaries.sum(:pageviews_count).to_i,
          summaries.where(pageviews_count: 1, has_non_pageview_events: false).count,
          summaries.sum(:visit_duration_seconds).to_f
        ]
      end

      def each_bucket(range)
        bucket_start = bucket_start_for(range.begin)
        bucket_end = bucket_start_for(effective_range_end(range))
        return if bucket_start.blank? || bucket_end.blank?

        while bucket_start <= bucket_end
          yield(bucket_start)
          bucket_start += 1.hour
        end
      end

      def normalize_site_id(site)
        case site
        when Analytics::Site
          site.id
        else
          site.presence
        end
      end

      def expected_full_bucket_count(range:)
        window = interior_bucket_window_for(range)
        return 0 if window.blank?

        bucket_starts_for(window).size
      end

      def raw_total_for_range(site:, range:, column:)
        visits = Analytics::FactStore.visit_relation(site:, started_at_range: range)

        case column.to_sym
        when :visits_count
          visits.count
        when :unique_visitors_count
          visits.distinct.count(:visitor_token)
        when :pageviews_count, :bounces_count, :total_visit_duration_seconds
          visit_ids = visits.pluck(:id)
          pageviews_count, bounces_count, total_visit_duration_seconds = visit_metric_totals_for_bucket(site:, visit_ids:)

          {
            pageviews_count: pageviews_count,
            bounces_count: bounces_count,
            total_visit_duration_seconds: total_visit_duration_seconds
          }.fetch(column.to_sym, 0)
        else
          0
        end
      end

      def raw_series_for_edges(range:, interval:, site:, column:)
        edge_ranges_for(range).each_with_object(Hash.new(0)) do |edge_range, result|
          grouped = raw_grouped_counts_for_range(site:, range: edge_range, interval:, column:)

          grouped.each do |bucket_time, value|
            result[normalize_bucket_time(bucket_time)] += value.to_i
          end
        end
      end

      def raw_grouped_counts_for_range(site:, range:, interval:, column:)
        bucket_sql = Analytics::Ranges.bucket_sql_for("#{Ahoy::Visit.table_name}.started_at", interval)
        visits = Analytics::FactStore.visit_relation(site:, started_at_range: range)

        case column.to_sym
        when :visits_count
          visits.group(Arel.sql(bucket_sql)).count
        when :unique_visitors_count
          visits.group(Arel.sql(bucket_sql)).distinct.count(:visitor_token)
        else
          {}
        end
      end

      def coerce_numeric(value)
        value.is_a?(Integer) ? value : value.to_f
      end
  end
end
