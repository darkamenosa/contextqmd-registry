# frozen_string_literal: true

class AnalyticsProfile::Directory
  include AnalyticsProfile::PayloadBuilder

  class << self
    def payload(query:, limit:, page:, search: nil)
      new(query:, limit:, page:, search:).payload
    end
  end

  def initialize(query:, limit:, page:, search:)
    @query = Analytics::Query.wrap(query)
    @limit = limit
    @page = page
    @search = search
  end

  def payload
    return projected_payload if projection_available?

    fallback_payload
  end

  private
    attr_reader :query, :limit, :page, :search

    def projection_available?
      AnalyticsProfile::Projection.available?
    end

    def projected_payload
      dataset_query = Analytics::ProfilesDatasetQuery.new(query:, limit:, page:, search:)
      profiles = dataset_query.page_records

      {
        kind: "profiles",
        results: serialize_profiles(profiles, dataset_query: dataset_query),
        meta: {
          has_more: dataset_query.has_more?
        }
      }
    end

    def fallback_payload
      rows = build_profile_rows_from_visits(scoped_profile_visits)
      rows = filter_profile_rows(rows)
      rows = rows.sort_by { |row| row[:last_seen_at].to_s }.reverse

      paginate_rows(rows)
    end

    def scoped_profile_visits
      raw_range, = Analytics::Ranges.range_and_interval_for(query.time_range_key, nil, query)
      range = Analytics::Ranges.trim_range_to_now_if_applicable(raw_range, query.time_range_key)

      Analytics::VisitScope
        .visits(range, query)
        .where.not(analytics_profile_id: nil)
    end

    def serialize_profiles(profiles, dataset_query:)
      summaries = dataset_query.summaries_by_profile
      latest_visits = dataset_query.latest_visits_by_profile
      total_visits = dataset_query.total_visits_by_profile
      recent_activity = recent_activity_by_profile(scoped_profile_visits, profiles.map(&:id))

      profiles.map do |profile|
        build_profile_row(
          profile,
          latest_visit: latest_visits[profile.read_attribute("latest_scoped_visit_id")],
          last_seen_at: profile.read_attribute("scoped_last_seen_at") || profile.last_seen_at,
          total_visits: total_visits[profile.id].to_i,
          scoped_visits: profile.read_attribute("scoped_visits").to_i,
          summary: summaries[profile.id],
          recent_activity: recent_activity[profile.id]
        )
      end
    end

    def build_profile_rows_from_visits(visits)
      aggregates = visits.group(:analytics_profile_id).pluck(:analytics_profile_id, Arel.sql("MAX(started_at)"), Arel.sql("COUNT(*)"))
      profile_ids = aggregates.map(&:first).compact
      return [] if profile_ids.empty?

      profiles = AnalyticsProfile.for_analytics_site.where(id: profile_ids).index_by(&:id)
      summaries =
        if AnalyticsProfile::Projection.available?
          AnalyticsProfileSummary.for_analytics_site.where(analytics_profile_id: profile_ids).index_by(&:analytics_profile_id)
        else
          {}
        end
      total_visits = Ahoy::Visit.for_analytics_site.where(analytics_profile_id: profile_ids).group(:analytics_profile_id).count
      latest_visits = latest_visits_by_profile(visits).index_by(&:analytics_profile_id)
      recent_activity = recent_activity_by_profile(visits, profile_ids)

      aggregates.map do |profile_id, last_seen_at, scoped_visits|
        profile = profiles[profile_id]
        next if profile.nil?

        build_profile_row(
          profile,
          latest_visit: latest_visits[profile_id],
          last_seen_at: last_seen_at,
          total_visits: total_visits[profile_id].to_i,
          scoped_visits: scoped_visits.to_i,
          summary: summaries[profile_id],
          recent_activity: recent_activity[profile_id]
        )
      end.compact
    end

    def recent_activity_by_profile(visits, profile_ids)
      return {} if profile_ids.empty?

      if AnalyticsProfile::Projection.available?
        recent_activity_by_profile_from_sessions(profile_ids)
      else
        recent_activity_by_profile_from_visits(visits, profile_ids)
      end
    end

    def recent_activity_by_profile_from_sessions(profile_ids)
      dates = recent_activity_dates
      activity_date_sql = AnalyticsProfile.sanitize_sql_array(
        [
          "DATE((analytics_profile_sessions.started_at AT TIME ZONE 'UTC') AT TIME ZONE ?)",
          recent_activity_time_zone
        ]
      )
      counts =
        AnalyticsProfileSession
          .for_analytics_site(::Analytics::Current.site)
          .where(analytics_profile_id: profile_ids)
          .where("analytics_profile_sessions.started_at >= ?", dates.first.beginning_of_day)
          .group(:analytics_profile_id, Arel.sql(activity_date_sql))
          .count

      profile_ids.index_with do |profile_id|
        dates.map { |date| counts.fetch([ profile_id, date ], 0) }
      end
    end

    def recent_activity_by_profile_from_visits(visits, profile_ids)
      dates = recent_activity_dates
      activity_date_sql = AnalyticsProfile.sanitize_sql_array(
        [
          "DATE((COALESCE(ahoy_events.time, ahoy_visits.started_at) AT TIME ZONE 'UTC') AT TIME ZONE ?)",
          recent_activity_time_zone
        ]
      )
      counts =
        visits
          .where(analytics_profile_id: profile_ids)
          .left_outer_joins(:events)
          .where("COALESCE(ahoy_events.time, ahoy_visits.started_at) >= ?", dates.first.beginning_of_day)
          .group(:analytics_profile_id, Arel.sql(activity_date_sql))
          .count(Arel.sql("DISTINCT ahoy_visits.id"))

      profile_ids.index_with do |profile_id|
        dates.map { |date| counts.fetch([ profile_id, date ], 0) }
      end
    end

    def recent_activity_dates
      @recent_activity_dates ||= 6.downto(0).map { |offset| Time.zone.today - offset }
    end

    def recent_activity_time_zone
      Time.zone.tzinfo.name
    end

    def latest_visits_by_profile(visits)
      visits
        .select("DISTINCT ON (analytics_profile_id) #{Ahoy::Visit.table_name}.*")
        .order(Arel.sql("analytics_profile_id, started_at DESC, id DESC"))
        .to_a
    end

    def filter_profile_rows(rows)
      return rows if search.blank?

      needle = search.to_s.strip.downcase
      return rows if needle.blank?

      rows.select do |row|
        [
          row[:name],
          row[:country],
          row[:city],
          row[:source],
          row[:browser],
          row[:os],
          row[:current_page]
        ].compact.any? { |value| value.to_s.downcase.include?(needle) }
      end
    end

    def paginate_rows(rows)
      offset = [ page.to_i - 1, 0 ].max * limit.to_i
      paged_rows = rows.slice(offset, limit.to_i) || []

      {
        kind: "profiles",
        results: paged_rows,
        meta: {
          has_more: offset + paged_rows.length < rows.length
        }
      }
    end
end
