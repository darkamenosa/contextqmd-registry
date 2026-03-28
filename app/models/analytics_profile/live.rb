# frozen_string_literal: true

class AnalyticsProfile::Live
  include AnalyticsProfile::PayloadBuilder
  RECENT_ACTIVITY_WINDOW = 10.minutes

  class << self
    def payload(now: Time.zone.now, window: 5.minutes, recent_window: RECENT_ACTIVITY_WINDOW)
      new(now:, window:, recent_window:).payload
    end

    def sessions(now: Time.zone.now, window: 5.minutes, recent_window: RECENT_ACTIVITY_WINDOW)
      new(now:, window:, recent_window:).sessions
    end
  end

  def initialize(now:, window:, recent_window:)
    @now = now
    @window = window
    @recent_window = recent_window
  end

  def payload
    active_visits = active_live_visits
    recent_events = recent_activity_events
    visits_by_id = visits_by_id(active_visits, recent_events)
    profiles_by_id = profiles_by_id(visits_by_id.values)
    total_visits_by_profile = total_visits_by_profile(profiles_by_id.keys)
    recent_events_by_visit = recent_events.group_by(&:visit_id)
    last_seen_by_visit = last_seen_by_visit(recent_events_by_visit, visits_by_id)
    active_visit_ids = active_visits.map(&:id)

    {
      live_sessions: build_live_sessions(
        active_visits,
        profiles_by_id:,
        total_visits_by_profile:,
        recent_events_by_visit:,
        last_seen_by_visit:
      ),
      recent_events: build_recent_events(
        recent_events,
        visits_by_id:,
        profiles_by_id:,
        total_visits_by_profile:,
        active_visit_ids:,
        last_seen_by_visit:
      )
    }
  end

  def sessions
    active_visits = active_live_visits
    recent_events = recent_activity_events
    visits_by_id = visits_by_id(active_visits, recent_events)
    profiles_by_id = profiles_by_id(visits_by_id.values)
    total_visits_by_profile = total_visits_by_profile(profiles_by_id.keys)
    recent_events_by_visit = recent_events.group_by(&:visit_id)
    last_seen_by_visit = last_seen_by_visit(recent_events_by_visit, visits_by_id)

    build_live_sessions(
      active_visits,
      profiles_by_id:,
      total_visits_by_profile:,
      recent_events_by_visit:,
      last_seen_by_visit:
    )
  end

  private
    attr_reader :now, :window, :recent_window

    def build_live_sessions(visits, profiles_by_id:, total_visits_by_profile:, recent_events_by_visit:, last_seen_by_visit:)
      return [] if visits.empty?

      visits.filter_map do |visit|
        profile = profiles_by_id[visit.analytics_profile_id]
        next if profile.nil?

        build_live_session_row(
          profile,
          visit: visit,
          recent_events: Array(recent_events_by_visit[visit.id]),
          total_visits: total_visits_by_profile[profile.id].to_i,
          active: true,
          last_seen_at: last_seen_by_visit[visit.id]
        )
      end.compact.sort_by { |row| row[:last_seen_at].to_s }.reverse
    end

    def active_live_visits
      Analytics::LiveState.active_visits(now:, window:)
        .where.not(analytics_profile_id: nil)
        .order(started_at: :desc, id: :desc)
        .to_a
    end

    def recent_activity_events
      Ahoy::Event
        .where("time >= ?", now - recent_window)
        .order(time: :desc, id: :desc)
        .limit(200)
        .to_a
    end

    def visits_by_id(active_visits, recent_events)
      event_visit_ids = recent_events.map(&:visit_id).compact.uniq
      visits = active_visits

      if event_visit_ids.any?
        visits += Ahoy::Visit
          .where(id: event_visit_ids)
          .where.not(analytics_profile_id: nil)
          .to_a
      end

      visits.uniq { |visit| visit.id }.index_by(&:id)
    end

    def profiles_by_id(visits)
      profile_ids = visits.map(&:analytics_profile_id).compact.uniq
      return {} if profile_ids.empty?

      AnalyticsProfile.where(id: profile_ids).index_by(&:id)
    end

    def total_visits_by_profile(profile_ids)
      return {} if profile_ids.empty?

      Ahoy::Visit.where(analytics_profile_id: profile_ids).group(:analytics_profile_id).count
    end

    def last_seen_by_visit(recent_events_by_visit, visits_by_id)
      visits_by_id.each_with_object({}) do |(visit_id, visit), rows|
        rows[visit_id] =
          recent_events_by_visit[visit_id]&.max_by { |event| [ event.time || Time.at(0), event.id ] }&.time ||
          visit.started_at
      end
    end

    def build_recent_events(events, visits_by_id:, profiles_by_id:, total_visits_by_profile:, active_visit_ids:, last_seen_by_visit:)
      return [] if events.empty?

      events
        .filter_map do |event|
          visit = visits_by_id[event.visit_id]
          next if visit.nil?

          profile = profiles_by_id[visit.analytics_profile_id]
          next if profile.nil?

          live_event = build_live_event(
            event,
            profile,
            visit,
            total_visits: total_visits_by_profile[profile.id].to_i,
            active: active_visit_ids.include?(visit.id),
            last_seen_at: last_seen_by_visit[visit.id]
          )
          next if live_event[:event_name] == "engagement"

          live_event
        end
        .first(50)
    end
end
