# frozen_string_literal: true

class Analytics::ProfilesDatasetQuery::Postgres < Analytics::DatasetQuery
  def page_records
    @page_records ||= begin
      records, @has_more = fetch_page(page_relation)
      records
    end
  end

  def has_more?
    page_records
    @has_more
  end

  def summaries_by_profile
    @summaries_by_profile ||= AnalyticsProfileSummary.where(analytics_profile_id: profile_ids).index_by(&:analytics_profile_id)
  end

  def latest_visits_by_profile
    @latest_visits_by_profile ||= Ahoy::Visit.where(id: latest_visit_ids).index_by(&:id)
  end

  def total_visits_by_profile
    @total_visits_by_profile ||= profile_ids.index_with do |profile_id|
      summaries_by_profile[profile_id]&.total_visits
    end.tap do |totals|
      missing_ids = totals.select { |_, total| total.nil? }.keys
      next if missing_ids.empty?

      Ahoy::Visit.where(analytics_profile_id: missing_ids).group(:analytics_profile_id).count.each do |profile_id, count|
        totals[profile_id] = count
      end

      missing_ids.each { |profile_id| totals[profile_id] ||= 0 }
    end
  end

  private
    def scoped_profile_visits
      @scoped_profile_visits ||= begin
        raw_range, = Analytics::Ranges.range_and_interval_for(query.time_range_key, nil, query)
        range = Analytics::Ranges.trim_range_to_now_if_applicable(raw_range, query.time_range_key)

        Analytics::VisitScope
          .visits(range, query)
          .where.not(analytics_profile_id: nil)
      end
    end

    def page_relation
      relation = AnalyticsProfile
        .with(
          scoped_profiles: scoped_profile_aggregates_relation,
          latest_scoped_visits: latest_scoped_visits_relation
        )
        .joins("INNER JOIN scoped_profiles ON scoped_profiles.analytics_profile_id = analytics_profiles.id")
        .joins("LEFT JOIN latest_scoped_visits ON latest_scoped_visits.analytics_profile_id = analytics_profiles.id")
        .left_outer_joins(:summary)
        .select(
          "analytics_profiles.*",
          "scoped_profiles.scoped_last_seen_at",
          "scoped_profiles.scoped_visits",
          "latest_scoped_visits.latest_scoped_visit_id"
        )
        .order(Arel.sql("scoped_profiles.scoped_last_seen_at DESC, analytics_profiles.id DESC"))

      apply_search(relation)
    end

    def scoped_profile_aggregates_relation
      scoped_profile_visits
        .select(
          "analytics_profile_id",
          "MAX(started_at) AS scoped_last_seen_at",
          "COUNT(*) AS scoped_visits"
        )
        .group(:analytics_profile_id)
    end

    def latest_scoped_visits_relation
      scoped_profile_visits
        .select(<<~SQL.squish)
          DISTINCT ON (analytics_profile_id)
          analytics_profile_id,
          id AS latest_scoped_visit_id,
          country,
          city,
          region,
          device_type,
          os,
          browser,
          source_label,
          referring_domain,
          landing_page
        SQL
        .order(Arel.sql("analytics_profile_id, started_at DESC, id DESC"))
    end

    def apply_search(relation)
      needle = search.to_s.strip.downcase
      return relation if needle.blank?

      pattern = "%#{AnalyticsProfile.sanitize_sql_like(needle)}%"

      relation.where(
        <<~SQL.squish,
          LOWER(COALESCE(analytics_profile_summaries.search_text, '')) LIKE :pattern
          OR LOWER(COALESCE(analytics_profile_summaries.display_name, analytics_profiles.traits->>'display_name', '')) LIKE :pattern
          OR LOWER(COALESCE(analytics_profile_summaries.email, analytics_profiles.traits->>'email', '')) LIKE :pattern
          OR LOWER(COALESCE(analytics_profile_summaries.latest_country_name, latest_scoped_visits.country, '')) LIKE :pattern
          OR LOWER(COALESCE(analytics_profile_summaries.latest_city, latest_scoped_visits.city, '')) LIKE :pattern
          OR LOWER(COALESCE(analytics_profile_summaries.latest_source, latest_scoped_visits.source_label, latest_scoped_visits.referring_domain, '')) LIKE :pattern
          OR LOWER(COALESCE(analytics_profile_summaries.latest_browser, latest_scoped_visits.browser, '')) LIKE :pattern
          OR LOWER(COALESCE(analytics_profile_summaries.latest_os, latest_scoped_visits.os, '')) LIKE :pattern
          OR LOWER(COALESCE(analytics_profile_summaries.latest_current_page, latest_scoped_visits.landing_page, '')) LIKE :pattern
        SQL
        pattern: pattern
      )
    end

    def profile_ids
      @profile_ids ||= page_records.map(&:id)
    end

    def latest_visit_ids
      @latest_visit_ids ||= page_records.filter_map { |profile| profile.read_attribute("latest_scoped_visit_id") }
    end
end
