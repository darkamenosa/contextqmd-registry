# frozen_string_literal: true

class Analytics::SiteLocationHourlyVisitorRollup < AnalyticsRecord
  self.table_name = "analytics_site_location_hourly_visitor_rollups"

  COALESCE_WINDOW = 1.second
  ROLLUP_DIMENSIONS = %w[countries regions cities].freeze
  DIMENSION_ALIASES = {
    "map" => "countries"
  }.freeze
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
      rows = Analytics::FactStore.location_rollup_rows(site: site_id, bucket_start: bucket)
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
        expected_bucket_count(range:, site:)
    rescue StandardError
      false
    end

    def counts_for(range:, site:, dimension:, search: nil)
      return {} unless available?

      relation = apply_search(scoped_range(range:, site:, dimension:), dimension:, search:)
      relation.group(:value).distinct.count(:visitor_token)
    end

    def dominant_country_codes_for(range:, site:, dimension:, values: nil)
      return {} unless available?

      relation = scoped_range(range:, site:, dimension:)
        .where.not(country_code: "")
      relation = relation.where(value: values) if values.present?

      best = {}

      relation.group(:value, :country_code).distinct.count(:visitor_token).each do |(value, country_code), count|
        current = best[value]
        next if current && current[:count].to_i >= count.to_i

        best[value] = { country_code: country_code, count: count.to_i }
      end

      best.transform_values { |entry| entry[:country_code] }
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

      def apply_search(relation, dimension:, search:)
        return relation if search.blank?

        normalized_dimension = normalize_dimension(dimension)
        return relation.none if normalized_dimension.blank?

        if normalized_dimension == "countries"
          matching_codes = Ahoy::Visit.matching_country_codes(search)
          matching_codes.any? ? relation.where(value: matching_codes) : relation.none
        else
          relation.where("LOWER(value) LIKE ?", Analytics::Search.contains_pattern(search))
        end
      end
      def expected_bucket_count(range:, site:)
        Analytics::FactStore
          .visit_relation(site:, started_at_range: range)
          .where.not(visitor_token: [ nil, "" ])
          .distinct
          .count(Arel.sql("DATE_TRUNC('hour', #{Ahoy::Visit.table_name}.started_at)"))
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
        value = dimension.to_s.presence || "countries"
        value = DIMENSION_ALIASES.fetch(value, value)
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
  end
end
