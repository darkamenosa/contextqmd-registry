# frozen_string_literal: true

require "uri"

class Analytics::VisitSummary < AnalyticsRecord
  self.table_name = "analytics_visit_summaries"

  COALESCE_WINDOW = 1.second

  alias_attribute :pageview_duration_seconds, :visit_duration_seconds

  belongs_to :visit, class_name: "Ahoy::Visit"
  belongs_to :analytics_site, class_name: "Analytics::Site"
  belongs_to :analytics_profile, class_name: "AnalyticsProfile", optional: true

  scope :for_analytics_site, ->(site = ::Analytics::Current.site_or_default) { Analytics::Scope.apply(all, site:) }

  class << self
    def available?
      connection.data_source_exists?(table_name)
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
      false
    end

    def refresh_later(visit:)
      return unless available?
      return if visit.blank? || visit.id.blank?
      return unless should_enqueue_refresh?(visit.id)

      Analytics::VisitSummaryRefreshJob.perform_later(visit)
    end

    def refresh_visit!(visit)
      return unless available?
      return if visit.blank?

      attributes = build_attributes_for_visit(visit)
      return if attributes.blank?

      upsert(
        attributes,
        unique_by: :index_analytics_visit_summaries_on_visit_id,
        update_only: attributes.keys - [ :visit_id, :created_at ],
        record_timestamps: false
      )
    end

    def usable_for_visit_ids?(visit_ids)
      return false unless available?

      ids = normalized_visit_ids(visit_ids)
      return false if ids.empty?

      where(visit_id: ids).count == ids.length
    rescue StandardError
      false
    end

    def usable_for_scope?(visits_scope)
      return false unless available?

      total_visits = visits_scope.count
      return false if total_visits.zero?

      where(visit_id: visits_scope.select(:id)).count == total_visits
    rescue StandardError
      false
    end

    def projection_for_visit(visit)
      return unless available?
      return if visit.blank? || visit.id.blank?

      if summary = find_by(visit_id: visit.id)
        return unless projection_backed?(summary)

        {
          event_names: Array(summary.event_names),
          page_paths: Array(summary.page_paths),
          pageviews_count: summary.pageviews_count.to_i,
          events_count: summary.events_count.to_i,
          last_event_at: summary.last_event_at,
          engaged_ms_total: summary.engaged_ms_total.to_i
        }
      end
    end

    private
      def build_attributes_for_visit(visit)
        existing_summary = find_by(visit_id: visit.id)
        event_rows = ordered_event_rows_for_visit(visit)
        analytics_site_id = visit.analytics_site_id || Analytics::SiteLocator.from_record(visit)&.id
        visitor_token = visit.visitor_token.to_s
        return if analytics_site_id.blank? || visitor_token.blank?

        pageview_rows = event_rows.select { |row| row[:name] == "pageview" }
        event_page_paths = fallback_projection_list(
          values: ordered_distinct_values(event_rows.map { |row| row[:event_page] }),
          existing_values: existing_summary&.page_paths
        )
        event_names = fallback_projection_list(
          values: ordered_distinct_values(event_rows.map { |row| row[:name] }),
          existing_values: existing_summary&.event_names
        )
        normalized_landing_page = normalized_landing_page_for_entry(visit.landing_page)
        entry_page = pageview_rows.first&.fetch(:pageview_path).to_s.presence || existing_summary&.entry_page.to_s.presence || normalized_landing_page
        exit_page = pageview_rows.last&.fetch(:pageview_path).to_s.presence || existing_summary&.exit_page.to_s.presence
        current_page = event_page_paths.last || existing_summary&.current_page.to_s.presence || exit_page.to_s.presence || normalized_landing_page
        last_event_at = event_rows.last&.fetch(:time) || existing_summary&.last_event_at
        resolved_country = Analytics::Country.resolve(
          country: visit.country,
          country_code: visit.respond_to?(:country_code) ? visit.country_code : nil
        )
        started_at = visit.started_at || last_event_at || Time.current
        pageviews_count = pageview_rows.any? ? pageview_rows.length : existing_summary&.pageviews_count.to_i
        visit_duration_seconds =
          if pageview_rows.any?
            pageview_duration_seconds(pageview_rows)
          else
            existing_summary&.visit_duration_seconds.to_f
          end
        has_non_pageview_events =
          if event_rows.any?
            event_rows.any? { |row| row[:name] != "pageview" }
          else
            existing_summary&.has_non_pageview_events || false
          end
        events_count = event_rows.any? ? event_rows.length : existing_summary&.events_count.to_i
        engaged_ms_total = event_rows.any? ? event_rows.sum { |row| row[:engaged_ms_total] } : existing_summary&.engaged_ms_total.to_i
        now = Time.current

        {
          visit_id: visit.id,
          analytics_profile_id: visit.analytics_profile_id,
          analytics_site_id: analytics_site_id,
          started_at: started_at,
          visitor_token: visitor_token,
          source: visit.source_label.to_s.presence || visit.referring_domain.to_s.presence || "Direct / None",
          country: resolved_country.name,
          country_code: resolved_country.code,
          region: visit.region.to_s.presence,
          city: visit.city.to_s.presence,
          device_type: visit.device_type.to_s.presence || "Desktop",
          os: visit.os.to_s.presence,
          browser: visit.browser.to_s.presence,
          entry_page: entry_page.to_s,
          exit_page: exit_page.to_s,
          current_page: current_page.to_s,
          pageviews_count: pageviews_count,
          visit_duration_seconds: visit_duration_seconds,
          duration_seconds: session_duration_seconds(started_at, last_event_at),
          has_non_pageview_events: has_non_pageview_events,
          last_event_at: last_event_at,
          events_count: events_count,
          engaged_ms_total: engaged_ms_total,
          event_names: event_names,
          page_paths: event_page_paths,
          created_at: now,
          updated_at: now
        }
      end

      def projection_backed?(summary)
        summary.events_count.present? &&
          summary.engaged_ms_total.present? &&
          !summary.event_names.nil? &&
          !summary.page_paths.nil?
      end

      def ordered_event_rows_for_visit(visit)
        Analytics::FactStore
          .ordered_events_for_visit(visit_id: visit.id, site: site_for_visit(visit))
          .map do |event|
            properties = event.properties.to_h
            event_page = properties["page"]

            {
              time: event.time.respond_to?(:to_time) ? event.time.to_time : event.time,
              name: event.name.to_s,
              event_page: event_page.to_s.presence,
              pageview_path: pageview_path_label(event_page),
              engaged_ms_total: engaged_ms_value(event.name, properties["engaged_ms"])
            }
          end
      end

      def pageview_duration_seconds(page_rows)
        return 0.0 if page_rows.length <= 1

        first_time = page_rows.first.fetch(:time)
        last_time = page_rows.last.fetch(:time)
        return 0.0 if first_time.blank? || last_time.blank?

        [ (last_time.to_time - first_time.to_time).to_f, 0.0 ].max
      end

      def session_duration_seconds(started_at, last_event_at)
        return 0 if started_at.blank?

        [ (last_event_at || started_at).to_i - started_at.to_i, 0 ].max
      end

      def ordered_distinct_values(values)
        values.each_with_object([]) do |value, result|
          next if value.blank? || result.include?(value)

          result << value
        end
      end

      def fallback_projection_list(values:, existing_values:)
        if values.any?
          values
        else
          Array(existing_values).filter_map(&:presence)
        end
      end

      def engaged_ms_value(name, value)
        return 0 unless name.to_s == "engagement"

        parsed = value.to_i
        parsed.positive? ? parsed : 0
      rescue StandardError
        0
      end

      def pageview_path_label(value)
        normalized = Analytics::Urls.normalized_path_only(value).presence
        return "(unknown)" if normalized.blank?

        normalized
      rescue URI::InvalidURIError
        value.to_s.presence || "(unknown)"
      end

      def normalized_landing_page_for_entry(value)
        normalized = Analytics::Urls.normalized_path_only(value).presence
        return "" if normalized.blank?
        return "" if Analytics::Pages.internal_entry_label?(normalized)

        normalized
      rescue URI::InvalidURIError
        value.to_s.presence || ""
      end

      def normalized_visit_ids(visit_ids)
        Array(visit_ids).flatten.compact.map(&:to_i).uniq
      end

      def site_for_visit(visit)
        visit.analytics_site || Analytics::SiteLocator.from_record(visit)
      end

      def should_enqueue_refresh?(visit_id)
        return true unless cache_available?

        Rails.cache.write(
          refresh_cache_key(visit_id),
          true,
          unless_exist: true,
          expires_in: COALESCE_WINDOW
        )
      rescue StandardError
        true
      end

      def refresh_cache_key(visit_id)
        [ "analytics", "visit-summary", visit_id ].join(":")
      end

      def cache_available?
        !Rails.cache.is_a?(ActiveSupport::Cache::NullStore)
      rescue StandardError
        false
      end
  end
end
