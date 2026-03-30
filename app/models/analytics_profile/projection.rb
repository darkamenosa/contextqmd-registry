# frozen_string_literal: true

require "uri"

class AnalyticsProfile::Projection
  class << self
    def available?
      AnalyticsProfileSummary.connection.data_source_exists?(AnalyticsProfileSummary.table_name) &&
        AnalyticsProfileSession.connection.data_source_exists?(AnalyticsProfileSession.table_name)
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
      false
    end

    def project_visit(visit, previous_profile_id: nil)
      return unless available?
      return if visit.blank?

      if visit.analytics_profile_id.present?
        upsert_session!(visit)
        refresh_summary(visit.analytics_profile_id)
      else
        AnalyticsProfileSession.where(visit_id: visit.id).delete_all
      end

      if previous_profile_id.present? && previous_profile_id != visit.analytics_profile_id
        refresh_summary(previous_profile_id)
      end
    end

    def rebuild(profile)
      return unless available?
      return if profile.blank?

      visits = Ahoy::Visit.for_analytics_site(profile.analytics_site).where(analytics_profile_id: profile.id).order(started_at: :desc, id: :desc).to_a
      visit_ids = visits.map(&:id)

      visits.each { |visit| upsert_session!(visit) }

      AnalyticsProfileSession
        .where(analytics_profile_id: profile.id)
        .where.not(visit_id: visit_ids)
        .delete_all

      refresh_summary(profile.id)
    end

    def ensure_profile!(profile)
      return unless available?
      return if profile.blank?

      summary = AnalyticsProfileSummary.find_by(analytics_profile_id: profile.id)
      session_count = AnalyticsProfileSession.for_analytics_site(profile.analytics_site).where(analytics_profile_id: profile.id).count

      if summary.nil? ||
          summary.total_sessions != session_count ||
          summary.display_name.blank? ||
          summary.search_text.blank?
        rebuild(profile)
      end
    end

    def merge_profiles!(from_profile_id:, to_profile_id:)
      return unless available?
      return if from_profile_id.blank? || to_profile_id.blank? || from_profile_id == to_profile_id

      AnalyticsProfileSession.where(analytics_profile_id: from_profile_id).update_all(
        analytics_profile_id: to_profile_id,
        analytics_site_id: AnalyticsProfile.find_by(id: to_profile_id)&.analytics_site_id,
        updated_at: Time.current
      )
      AnalyticsProfileSummary.where(analytics_profile_id: from_profile_id).delete_all
      refresh_summary(to_profile_id)
    end

    def refresh_summary(profile_or_id)
      profile_id = profile_or_id.respond_to?(:id) ? profile_or_id.id : profile_or_id
      refresh_summary_by_id(profile_id)
    end

    private
      def upsert_session!(visit)
        return if visit.analytics_profile_id.blank?

        events = Ahoy::Event.where(visit_id: visit.id).order(time: :asc, id: :asc).to_a
        event_names = events.map(&:name).compact.uniq
        page_paths = events.filter_map { |event| page_for_event(event) }.uniq
        pageviews = events.count { |event| event.name == "pageview" }
        last_event_at = events.map(&:time).compact.max || visit.started_at
        engaged_ms_total = total_engaged_ms(events)
        source = visit.source_label.to_s.presence || visit.referring_domain.to_s.presence || "Direct / None"
        entry_page = page_paths.first || normalized_path(visit.landing_page)
        exit_page = page_paths.last || normalized_path(visit.landing_page)

        with_session_retry do
          session = AnalyticsProfileSession.find_or_initialize_by(visit_id: visit.id)
          resolved_country = Analytics::Country.resolve(
            country: visit.country,
            country_code: visit.respond_to?(:country_code) ? visit.country_code : nil
          )
          session.analytics_profile_id = visit.analytics_profile_id
          session.analytics_site_id = visit.analytics_site_id
          session.started_at = visit.started_at || last_event_at || Time.current
          session.last_event_at = last_event_at
          session.country = resolved_country.name
          session.country_code = resolved_country.code if session.respond_to?(:country_code=)
          session.region = visit.region.to_s.presence
          session.city = visit.city.to_s.presence
          session.device_type = visit.device_type.to_s.presence || "Desktop"
          session.os = visit.os.to_s.presence
          session.browser = visit.browser.to_s.presence
          session.source = source
          session.entry_page = entry_page
          session.exit_page = exit_page
          session.current_page = exit_page
          session.duration_seconds = duration_seconds(session.started_at, last_event_at)
          session.engaged_ms_total = engaged_ms_total if session.respond_to?(:engaged_ms_total=)
          session.pageviews_count = pageviews
          session.events_count = events.size
          session.page_paths = page_paths
          session.event_names = event_names
          session.save!
        end
      end

      def with_session_retry(max_attempts = 2)
        attempts = 0

        begin
          attempts += 1
          yield
        rescue ActiveRecord::RecordNotUnique, PG::UniqueViolation, ActiveRecord::StatementInvalid => error
          raise unless unique_session_conflict?(error)
          raise if attempts >= max_attempts

          retry
        end
      end

      def unique_session_conflict?(error)
        return true if error.is_a?(ActiveRecord::RecordNotUnique)
        return true if defined?(PG::UniqueViolation) && error.is_a?(PG::UniqueViolation)

        cause = error.respond_to?(:cause) ? error.cause : nil
        return true if cause.is_a?(ActiveRecord::RecordNotUnique)
        return true if defined?(PG::UniqueViolation) && cause.is_a?(PG::UniqueViolation)

        error.message.to_s.include?("index_analytics_profile_sessions_on_visit_id")
      end

      def refresh_summary_by_id(profile_id)
        return if profile_id.blank?

        profile = AnalyticsProfile.find_by(id: profile_id)
        return if profile.blank?

        sessions = AnalyticsProfileSession.for_analytics_site(profile.analytics_site).where(analytics_profile_id: profile_id).order(started_at: :desc, id: :desc).to_a
        if sessions.empty?
          AnalyticsProfileSummary.for_analytics_site(profile.analytics_site).where(analytics_profile_id: profile_id).delete_all
          return
        end

        latest_session = sessions.max_by { |session| [ session.last_event_at || session.started_at, session.id ] }
        visit_ids = sessions.map(&:visit_id)
        top_pages = top_pages_for_visits(visit_ids)

        summary = AnalyticsProfileSummary.find_or_initialize_by(analytics_profile_id: profile_id)
        session_last_seen_times = sessions.map { |session| session.last_event_at || session.started_at }.compact
        summary.analytics_site_id = profile.analytics_site_id
        summary.first_seen_at = [ profile.first_seen_at, sessions.map(&:started_at).compact.min ].compact.min || profile.first_seen_at || Time.current
        summary.last_seen_at = [ profile.last_seen_at, session_last_seen_times.max ].compact.max || profile.last_seen_at || Time.current
        summary.last_event_at = [ profile.last_event_at, sessions.map(&:last_event_at).compact.max ].compact.max
        summary.latest_visit_id = latest_session.visit_id
        summary.total_visits = Ahoy::Visit.for_analytics_site(profile.analytics_site).where(analytics_profile_id: profile_id).count
        summary.total_sessions = sessions.length
        summary.total_pageviews = sessions.sum(&:pageviews_count)
        summary.total_events = sessions.sum(&:events_count)
        summary.latest_context = build_latest_context(latest_session)
        summary.display_name = resolved_display_name(profile, latest_session)
        summary.email = trait_value(profile, "email")
        summary.latest_country_name = latest_country_name(latest_session)
        summary.latest_country_code = latest_session.respond_to?(:country_code) ? latest_session.country_code : nil
        summary.latest_region = latest_session.region
        summary.latest_city = latest_session.city
        summary.latest_source = latest_session.source
        summary.latest_browser = latest_session.browser
        summary.latest_os = latest_session.os
        summary.latest_device_type = latest_session.device_type
        summary.latest_current_page = latest_session.current_page
        summary.devices_used = ranked_values(sessions, &:device_type)
        summary.browsers_used = ranked_values(sessions, &:browser)
        summary.oses_used = ranked_values(sessions, &:os)
        summary.sources_used = ranked_values(sessions, &:source)
        summary.locations_used = ranked_locations(sessions)
        summary.top_pages = top_pages
        summary.search_text = build_search_text(summary)
        summary.save!

        profile.update_columns(
          stats: profile.stats.to_h.merge(
            "total_visits" => summary.total_visits,
            "total_sessions" => summary.total_sessions,
            "total_pageviews" => summary.total_pageviews,
            "total_events" => summary.total_events
          ),
          updated_at: Time.current
        )
      end

      def top_pages_for_visits(visit_ids)
        return [] if visit_ids.empty?

        Ahoy::Event
          .for_analytics_site(::Analytics::Current.site)
          .where(visit_id: visit_ids, name: "pageview")
          .group(Arel.sql("ahoy_events.properties->>'page'"))
          .order(Arel.sql("COUNT(*) DESC"))
          .limit(6)
          .count
          .filter_map do |page, count|
            next if page.blank?

            { "label" => page, "count" => count }
          end
      end

      def build_latest_context(session)
        return {} if session.blank?

        {
          "source" => session.source,
          "device_type" => session.device_type,
          "os" => session.os,
          "browser" => session.browser,
          "country_code" => session.respond_to?(:country_code) ? session.country_code : nil,
          "region" => session.region,
          "city" => session.city,
          "current_page" => session.current_page,
          "started_at" => session.started_at&.iso8601,
          "last_event_at" => session.last_event_at&.iso8601
        }.compact
      end

      def build_search_text(summary)
        [
          summary.display_name,
          summary.email,
          summary.latest_country_name,
          summary.latest_city,
          summary.latest_region,
          summary.latest_source,
          summary.latest_browser,
          summary.latest_os,
          summary.latest_device_type,
          summary.latest_current_page
        ].filter_map { |value| value.to_s.strip.presence }.uniq.join(" ")
      end

      def latest_country_name(session)
        return if session.blank?

        Analytics::Country::Label.name_for(session.respond_to?(:country_code) ? session.country_code : nil).presence ||
          session.country.to_s.presence
      end

      def trait_value(profile, key)
        profile.traits.to_h[key].to_s.presence
      rescue StandardError
        nil
      end

      def resolved_display_name(profile, latest_session)
        trait_value(profile, "display_name").presence ||
          resolved_identity_display_name(profile, latest_session).presence ||
          profile.display_name
      end

      def resolved_identity_display_name(profile, latest_session)
        identity =
          if latest_session&.visit_id.present?
            visit_user_id = Ahoy::Visit.where(id: latest_session.visit_id).pick(:user_id)
            visit_user_id.present? ? Identity.find_by(id: visit_user_id) : nil
          end

        if identity.blank?
          identity_key = profile.profile_keys.find { |key| key.kind == "identity_id" }
          identity = Identity.find_by(id: identity_key.value) if identity_key&.value.present?
        end

        identity&.display_name.to_s.presence
      rescue StandardError
        nil
      end

      def ranked_values(sessions)
        counts = Hash.new { |hash, key| hash[key] = { "label" => key, "count" => 0, "last_seen_at" => nil } }

        sessions.each do |session|
          value = yield(session).to_s.presence
          next if value.blank?

          item = counts[value]
          item["count"] += 1
          item["last_seen_at"] = [ item["last_seen_at"], (session.last_event_at || session.started_at)&.iso8601 ].compact.max
        end

        counts.values.sort_by { |item| [ -item["count"], item["label"] ] }
      end

      def ranked_locations(sessions)
        counts = {}

        sessions.each do |session|
          next if session.country_code.blank? && session.city.blank? && session.region.blank?

          key = [ session.respond_to?(:country_code) ? session.country_code : nil, session.region, session.city ]
          counts[key] ||= {
            "country_code" => session.respond_to?(:country_code) ? session.country_code : nil,
            "region" => session.region,
            "city" => session.city,
            "count" => 0,
            "last_seen_at" => nil
          }
          counts[key]["count"] += 1
          counts[key]["last_seen_at"] = [ counts[key]["last_seen_at"], (session.last_event_at || session.started_at)&.iso8601 ].compact.max
        end

        counts.values.sort_by { |item| [ -item["count"], item["label"] ] }
      end

      def page_for_event(event)
        event.properties.to_h.with_indifferent_access[:page].presence
      rescue StandardError
        nil
      end

      def normalized_path(value)
        return if value.blank?

        uri = URI.parse(value.to_s)
        path = uri.path.to_s.presence || "/"
        query = uri.query.to_s.presence
        query ? "#{path}?#{query}" : path
      rescue URI::InvalidURIError
        value.to_s
      end

      def duration_seconds(started_at, last_event_at)
        return 0 if started_at.blank?

        [ (last_event_at || started_at).to_i - started_at.to_i, 0 ].max
      end

      def total_engaged_ms(events)
        events.sum do |event|
          next 0 unless event.name.to_s == "engagement"

          engaged_ms = event.properties.to_h.with_indifferent_access[:engaged_ms]
          [ engaged_ms.to_i, 0 ].max
        rescue StandardError
          0
        end
      end
  end
end
