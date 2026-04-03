# frozen_string_literal: true

class Analytics::SiteEventHourlyRollup < AnalyticsRecord
  self.table_name = "analytics_site_event_hourly_rollups"

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

      totals = Analytics::FactStore.event_totals_for_bucket(site: site_id, bucket_start: bucket)
      events_count = totals.fetch(:events_count, 0).to_i
      pageviews_count = totals.fetch(:pageviews_count, 0).to_i

      now = Time.current
      upsert(
        {
          analytics_site_id: site_id,
          bucket_start: bucket,
          events_count: events_count,
          pageviews_count: pageviews_count,
          created_at: now,
          updated_at: now
        },
        unique_by: :idx_site_event_hourly_rollups_on_site_bucket
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

    def sum_for(range:, site:, column: :pageviews_count)
      return 0 unless available?

      rollup_total = scoped_full_buckets(range:, site:).sum(column)
      edge_total = edge_ranges_for(range).sum { |edge_range| raw_total_for_range(site:, range: edge_range, column:) }

      rollup_total.to_i + edge_total.to_i
    end

    def series_for(range:, interval:, site:, column: :pageviews_count)
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

    private
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
        case column.to_sym
        when :pageviews_count
          Analytics::FactStore.pageview_relation(site:, range:).count
        when :events_count
          Analytics::FactStore.event_relation(site:, range:).count
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
        bucket_sql = Analytics::Ranges.bucket_sql_for("#{Ahoy::Event.table_name}.time", interval)
        relation =
          case column.to_sym
          when :pageviews_count
            Analytics::FactStore.pageview_relation(site:, range:)
          when :events_count
            Analytics::FactStore.event_relation(site:, range:)
          else
            return {}
          end

        relation.group(Arel.sql(bucket_sql)).count
      end
  end
end
