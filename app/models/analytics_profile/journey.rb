# frozen_string_literal: true

class AnalyticsProfile::Journey
  include AnalyticsProfile::PayloadBuilder

  class << self
    def payload(public_id:, query: nil)
      new(public_id:, query:).payload
    end

    def sessions_list_payload(public_id:, limit:, page:, date: nil)
      new(public_id:, date:).sessions_list_payload(limit:, page:)
    end

    def session_payload(public_id:, visit_id:, query: nil)
      new(public_id:, query:).session_payload(visit_id:)
    end
  end

  def initialize(public_id:, query: nil, date: nil)
    @public_id = public_id
    @query = Analytics::Query.wrap(query)
    @date = date
  end

  def payload
    ensure_projection!

    latest_profile_visit = latest_visit
    summary_record = summary
    activity = profile_activity_payload(profile)
    total_visits = summary_record&.total_visits || visits_scope.count
    total_sessions = summary_record&.total_sessions || fallback_total_sessions

    {
      profile: build_profile_row(
        profile,
        latest_visit: latest_profile_visit,
        last_seen_at: latest_profile_visit&.started_at || profile.last_seen_at,
        total_visits: total_visits,
        scoped_visits: total_visits,
        summary: summary_record
      ),
      summary: {
        sessions: total_sessions,
        pageviews: summary_record&.total_pageviews || 0,
        events: summary_record&.total_events || 0
      },
      activity: activity
    }
  end

  def sessions_list_payload(limit:, page:)
    ensure_projection!

    return fallback_sessions_list_payload(limit:, page:) unless projected?

    dataset_query = Analytics::ProfileSessionsDatasetQuery.new(
      profile:,
      limit:,
      page:,
      date: date
    )
    sessions = dataset_query.page_records

    {
      sessions: sessions.map { |session| serialize_session(session) },
      has_more: dataset_query.has_more?
    }
  end

  def session_payload(visit_id:)
    raise ActiveRecord::RecordNotFound unless projected?

    ensure_projection!

    visit = Ahoy::Visit.where(analytics_profile_id: profile.id, id: visit_id).take!
    session = AnalyticsProfileSession.find_by!(analytics_profile_id: profile.id, visit_id: visit.id)
    events = filtered_session_events(visit.id, query)
    journey_events = dedupe_session_events(
      events.map { |event| build_journey_event(event, visit) }
    )

    {
      session: serialize_session(session),
      source_summary: build_session_source_summary(visit),
      events: journey_events
    }
  end

  private
    attr_reader :public_id, :query
    attr_reader :date

    def profile
      @profile ||= AnalyticsProfile.find_by!(public_id: public_id)
    end

    def visits_scope
      @visits_scope ||= begin
        scope = Ahoy::Visit.where(analytics_profile_id: profile.id)
        scope = scope.where(started_at: date.beginning_of_day..date.end_of_day) if date
        scope.order(started_at: :desc, id: :desc)
      end
    end

    def latest_visit
      @latest_visit ||= begin
        latest_visit_id = summary&.latest_visit_id
        latest_visit_id.present? ? Ahoy::Visit.find_by(id: latest_visit_id) : visits_scope.first
      end
    end

    def summary
      return unless projected?

      @summary ||= AnalyticsProfileSummary.find_by(analytics_profile_id: profile.id)
    end

    def sessions_scope
      @sessions_scope ||= begin
        scope = AnalyticsProfileSession.where(analytics_profile_id: profile.id)
        scope = scope.where(started_at: date.beginning_of_day..date.end_of_day) if date
        scope.order(started_at: :desc, id: :desc)
      end
    end

    def ensure_projection!
      AnalyticsProfile::Projection.ensure_profile!(profile) if projected?
    end

    def projected?
      AnalyticsProfile::Projection.available?
    end

    def fallback_total_sessions
      projected? ? sessions_scope.count : visits_scope.count
    end

    def fallback_sessions_list_payload(limit:, page:)
      sessions = profile_sessions_payload(profile, visits_scope.to_a)
      offset = [ page.to_i - 1, 0 ].max * limit.to_i
      paged = sessions.slice(offset, limit.to_i) || []

      {
        sessions: paged,
        has_more: offset + paged.length < sessions.length
      }
    end
end
