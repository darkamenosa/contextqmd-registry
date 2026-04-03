# frozen_string_literal: true

class AnalyticsProfile::Projection
  class << self
    def available?
      AnalyticsProfileSummary.connection.data_source_exists?(AnalyticsProfileSummary.table_name) &&
        Analytics::VisitSummary.connection.data_source_exists?(Analytics::VisitSummary.table_name)
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
      false
    end

    def project_visit(visit, previous_profile_id: nil, async_summary: false)
      return unless available?
      return if visit.blank?

      refresh_visit_summary!(visit)

      if visit.analytics_profile_id.present?
        refresh_profile_summary(visit.analytics_profile_id, async: async_summary)
      end

      if previous_profile_id.present? && previous_profile_id != visit.analytics_profile_id
        refresh_profile_summary(previous_profile_id, async: async_summary)
      end
    end

    def rebuild(profile)
      return unless available?
      return if profile.blank?

      visits = Analytics::FactStore.visit_relation(
        site: profile.analytics_site,
        analytics_profile_ids: [ profile.id ],
        order: { started_at: :desc, id: :desc }
      ).to_a
      visit_ids = visits.map(&:id)

      visits.each { |visit| refresh_visit_summary!(visit) }
      refresh_stale_visit_summaries(profile, visit_ids)

      refresh_summary(profile.id)
    end

    def ensure_profile!(profile)
      return unless available?
      return if profile.blank?

      summary = AnalyticsProfileSummary.find_by(analytics_profile_id: profile.id)
      session_count = Analytics::VisitSummary.for_analytics_site(profile.analytics_site).where(analytics_profile_id: profile.id).count

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

      Analytics::VisitSummary.where(analytics_profile_id: from_profile_id).update_all(
        analytics_profile_id: to_profile_id,
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
      def refresh_profile_summary(profile_id, async:)
        return if profile_id.blank?

        if async
          AnalyticsProfile.find_by(id: profile_id)&.rebuild_summary_later
        else
          refresh_summary(profile_id)
        end
      end

      def refresh_visit_summary!(visit)
        Analytics::VisitSummary.refresh_visit!(visit)
      end

      def refresh_summary_by_id(profile_id)
        return if profile_id.blank?

        profile = AnalyticsProfile.find_by(id: profile_id)
        return if profile.blank?

        sessions_scope = Analytics::VisitSummary.for_analytics_site(profile.analytics_site).where(analytics_profile_id: profile_id)
        aggregate = summary_aggregate_for_scope(sessions_scope)

        if aggregate[:total_sessions].zero?
          AnalyticsProfileSummary.for_analytics_site(profile.analytics_site).where(analytics_profile_id: profile_id).delete_all
          return
        end

        latest_session = latest_session_for_scope(sessions_scope)
        top_pages = top_pages_for_scope(sessions_scope)
        now = Time.current
        attributes = {
          analytics_profile_id: profile_id,
          analytics_site_id: profile.analytics_site_id,
          first_seen_at: [ profile.first_seen_at, aggregate[:first_started_at] ].compact.min || profile.first_seen_at || now,
          last_seen_at: [ profile.last_seen_at, aggregate[:last_seen_at] ].compact.max || profile.last_seen_at || now,
          last_event_at: [ profile.last_event_at, aggregate[:last_event_at] ].compact.max,
          latest_visit_id: latest_session.visit_id,
          total_visits: aggregate[:total_sessions],
          total_sessions: aggregate[:total_sessions],
          total_pageviews: aggregate[:total_pageviews],
          total_events: aggregate[:total_events],
          latest_context: build_latest_context(latest_session),
          display_name: resolved_display_name(profile, latest_session),
          email: trait_value(profile, "email"),
          latest_country_name: latest_country_name(latest_session),
          latest_country_code: latest_session.respond_to?(:country_code) ? latest_session.country_code : nil,
          latest_region: latest_session.region,
          latest_city: latest_session.city,
          latest_source: latest_session.source,
          latest_browser: latest_session.browser,
          latest_os: latest_session.os,
          latest_device_type: latest_session.device_type,
          latest_current_page: latest_session.current_page,
          devices_used: ranked_values_for_scope(sessions_scope, :device_type),
          browsers_used: ranked_values_for_scope(sessions_scope, :browser),
          oses_used: ranked_values_for_scope(sessions_scope, :os),
          sources_used: ranked_values_for_scope(sessions_scope, :source),
          locations_used: ranked_locations_for_scope(sessions_scope),
          top_pages:,
          created_at: now,
          updated_at: now
        }
        summary = AnalyticsProfileSummary.new(attributes.except(:created_at, :updated_at))
        attributes[:search_text] = build_search_text(summary)

        AnalyticsProfileSummary.upsert(
          attributes,
          unique_by: :index_analytics_profile_summaries_on_analytics_profile_id,
          update_only: attributes.keys - [ :analytics_profile_id, :created_at ],
          record_timestamps: false
        )

        profile.update_columns(
          stats: profile.stats.to_h.merge(
            "total_visits" => attributes[:total_visits],
            "total_sessions" => attributes[:total_sessions],
            "total_pageviews" => attributes[:total_pageviews],
            "total_events" => attributes[:total_events]
          ),
          updated_at: now
        )
      end

      def latest_session_for_scope(scope)
        scope
          .order(Arel.sql("COALESCE(last_event_at, started_at) DESC"), id: :desc)
          .first
      end

      def refresh_stale_visit_summaries(profile, visit_ids)
        Analytics::VisitSummary
          .for_analytics_site(profile.analytics_site)
          .where(analytics_profile_id: profile.id)
          .where.not(visit_id: visit_ids)
          .includes(:visit)
          .find_each do |summary|
            if summary.visit.present?
              refresh_visit_summary!(summary.visit)
            else
              summary.delete
            end
          end
      end

      def summary_aggregate_for_scope(scope)
        first_started_at, last_seen_at, last_event_at, total_sessions, total_pageviews, total_events =
          scope.pick(
            Arel.sql("MIN(started_at)"),
            Arel.sql("MAX(COALESCE(last_event_at, started_at))"),
            Arel.sql("MAX(last_event_at)"),
            Arel.sql("COUNT(*)"),
            Arel.sql("COALESCE(SUM(pageviews_count), 0)"),
            Arel.sql("COALESCE(SUM(events_count), 0)")
          )

        {
          first_started_at:,
          last_seen_at:,
          last_event_at:,
          total_sessions: total_sessions.to_i,
          total_pageviews: total_pageviews.to_i,
          total_events: total_events.to_i
        }
      end

      def top_pages_for_scope(scope)
        page_counts = Hash.new(0)

        # Keep profile summary refresh on projected session rows instead of
        # rescanning raw pageview facts. Counts reflect sessions containing a
        # page, which is sufficient for this profile-level hint list.
        scope
          .where.not(page_paths: [ nil, [] ])
          .pluck(:page_paths)
          .each do |paths|
            Array(paths).each do |page|
              normalized_page = page.to_s.presence
              next if normalized_page.blank?

              page_counts[normalized_page] += 1
            end
          end

        page_counts
          .sort_by { |page, count| [ -count, page ] }
          .first(6)
          .map do |page, count|
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
            visit_user_id = Analytics::FactStore.visit(visit_id: latest_session.visit_id, site: profile.analytics_site)&.user_id
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

      def ranked_values_for_scope(scope, column)
        quoted_column = Analytics::VisitSummary.connection.quote_column_name(column)

        scope
          .where(Arel.sql("NULLIF(#{quoted_column}, '') IS NOT NULL"))
          .group(column)
          .order(Arel.sql("COUNT(*) DESC"), Arel.sql("#{quoted_column} ASC"))
          .pluck(column, Arel.sql("COUNT(*)"), Arel.sql("MAX(COALESCE(last_event_at, started_at))"))
          .filter_map do |value, count, last_seen_at|
            next if value.blank?

            {
              "label" => value,
              "count" => count.to_i,
              "last_seen_at" => last_seen_at&.iso8601
            }
          end
      end

      def ranked_locations_for_scope(scope)
        scope
          .where(
            Arel.sql(
              "NULLIF(country_code, '') IS NOT NULL OR NULLIF(region, '') IS NOT NULL OR NULLIF(city, '') IS NOT NULL"
            )
          )
          .group(:country_code, :region, :city)
          .order(Arel.sql("COUNT(*) DESC"), :country_code, :region, :city)
          .pluck(
            :country_code,
            :region,
            :city,
            Arel.sql("COUNT(*)"),
            Arel.sql("MAX(COALESCE(last_event_at, started_at))")
          )
          .map do |country_code, region, city, count, last_seen_at|
            {
              "country_code" => country_code.presence,
              "region" => region.presence,
              "city" => city.presence,
              "count" => count.to_i,
              "last_seen_at" => last_seen_at&.iso8601
            }
          end
      end
  end
end
