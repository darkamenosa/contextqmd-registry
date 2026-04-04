# frozen_string_literal: true

class Analytics::SitePageHourlyRollup < AnalyticsRecord
  self.table_name = "analytics_site_page_hourly_rollups"

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

      rows = Analytics::FactStore.page_rollup_rows(site: site_id, bucket_start: bucket)

      transaction do
        where(analytics_site_id: site_id, bucket_start: bucket).delete_all
        upsert_all(
          rows,
          unique_by: :idx_site_page_hourly_rollups_unique,
          update_only: [ :pageviews_count, :updated_at ],
          record_timestamps: false
        ) if rows.any?
      end
    end

    def refresh_range!(site:, range:)
      return unless available?

      each_bucket(range) { |bucket_start| refresh_bucket!(site:, bucket_start:) }
    end

    def usable_for?(range:, site:)
      return false unless available?
      return false unless full_hour_aligned_range?(range)
      return false unless Analytics::SiteEventHourlyRollup.usable_for?(range:, site:)

      scoped_range(range:, site:).distinct.count(:bucket_start) == expected_bucket_count(range:, site:)
    rescue StandardError
      false
    end

    def counts_for(range:, site:, search: nil)
      return {} unless available?

      apply_search(scoped_range(range:, site:), search:)
        .group(:page_path)
        .distinct
        .count(:visitor_token)
    end

    def pageviews_for(range:, site:, search: nil)
      return {} unless available?

      apply_search(scoped_range(range:, site:), search:)
        .group(:page_path)
        .sum(:pageviews_count)
        .transform_values(&:to_i)
    end

    private
      def scoped_range(range:, site:)
        site_id = normalize_site_id(site)
        window = bucket_window_for(range)
        return none if site_id.blank? || window.blank?

        where(analytics_site_id: site_id, bucket_start: window)
      end

      def apply_search(relation, search:)
        return relation if search.blank?

        relation.where("LOWER(page_path) LIKE ?", Analytics::Search.contains_pattern(search))
      end
      def expected_bucket_count(range:, site:)
        Analytics::FactStore
          .pageview_relation(site:, range:)
          .joins(:visit)
          .where.not(ahoy_visits: { visitor_token: [ nil, "" ] })
          .distinct
          .count(Arel.sql("DATE_TRUNC('hour', #{Ahoy::Event.table_name}.time)"))
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
  end
end
