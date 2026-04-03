# frozen_string_literal: true

class Analytics::SiteSourceHourlyVisitorRollup < AnalyticsRecord
  self.table_name = "analytics_site_source_hourly_visitor_rollups"

  COALESCE_WINDOW = 1.second
  ROLLUP_DIMENSIONS = %w[all channels referrers utm-medium utm-source utm-campaign utm-content utm-term].freeze
  SPARSE_DIMENSIONS = %w[utm-source utm-campaign utm-content utm-term].freeze
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

      where(analytics_site_id: site_id, bucket_start: bucket).delete_all
      rows = Analytics::FactStore.source_rollup_rows(site: site_id, bucket_start: bucket)
      insert_all!(rows) if rows.any?
    end

    def refresh_range!(site:, range:)
      return unless available?

      each_bucket(range) { |bucket_start| refresh_bucket!(site:, bucket_start:) }
    end

    def usable_for?(range:, site:, dimension:)
      return false unless available?
      return false unless full_hour_aligned_range?(range)
      return false unless Analytics::SiteVisitHourlyRollup.usable_for?(range:, site:)

      normalized_dimension = normalize_dimension(dimension)
      return false if normalized_dimension.blank?

      scoped_range(range:, site:, dimension: normalized_dimension).distinct.count(:bucket_start) ==
        expected_bucket_count(range:, site:, dimension: normalized_dimension)
    rescue StandardError
      false
    end

    def counts_for(range:, site:, dimension:, search: nil)
      return {} unless available?

      relation = scoped_range(range:, site:, dimension:)
      relation = relation.where("LOWER(value) LIKE ?", Analytics::Search.contains_pattern(search)) if search.present?
      relation.group(:value).distinct.count(:visitor_token)
    end

    private
      def scoped_range(range:, site:, dimension:)
        site_id = normalize_site_id(site)
        normalized_dimension = normalize_dimension(dimension)
        window = bucket_window_for(range)
        return none if site_id.blank? || window.blank? || normalized_dimension.blank?

        where(
          analytics_site_id: site_id,
          dimension: normalized_dimension,
          bucket_start: window
        )
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

      def normalize_dimension(dimension)
        value = dimension.to_s.presence || "all"
        value = "utm-term" if value == "search-terms"
        value if ROLLUP_DIMENSIONS.include?(value)
      end

      def normalize_site_id(site)
        case site
        when Analytics::Site
          site.id
        else
          site.presence
        end
      end

      def expected_bucket_count(range:, site:, dimension:)
        relation = Analytics::FactStore.visit_relation(site:, started_at_range: range)
          .where.not(visitor_token: [ nil, "" ])

        relation =
          case dimension
          when "utm-medium"
            relation.where.not(utm_medium: [ nil, "" ])
          when "utm-source"
            relation.where.not(utm_source: [ nil, "" ])
          when "utm-campaign"
            relation.where.not(utm_campaign: [ nil, "" ])
          when "utm-content"
            relation.where.not(utm_content: [ nil, "" ])
          when "utm-term"
            relation.where.not(utm_term: [ nil, "" ])
          else
            relation
          end

        relation.distinct.count(Arel.sql("DATE_TRUNC('hour', #{Ahoy::Visit.table_name}.started_at)"))
      end
  end
end
