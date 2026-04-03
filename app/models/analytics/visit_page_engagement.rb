# frozen_string_literal: true

require "uri"

class Analytics::VisitPageEngagement < AnalyticsRecord
  self.table_name = "analytics_visit_page_engagements"

  COALESCE_WINDOW = 1.second

  belongs_to :visit, class_name: "Ahoy::Visit"
  belongs_to :analytics_site, class_name: "Analytics::Site"

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

      Analytics::VisitPageEngagementRefreshJob.perform_later(visit)
    end

    def refresh_visit!(visit)
      return unless available?
      return if visit.blank?

      attributes = build_attributes_for_visit(visit)

      transaction do
        where(visit_id: visit.id).delete_all
        insert_all!(attributes) if attributes.any?
      end
    end

    def usable_for_visit_ids?(visit_ids)
      return false unless available?

      ids = normalized_visit_ids(visit_ids)
      return false if ids.empty?

      where(visit_id: ids).distinct.count(:visit_id) == ids.length
    rescue StandardError
      false
    end

    def metrics_for_grouped_visits(grouped_visit_ids)
      names = grouped_visit_ids.keys.map { |name| page_label(name) }.uniq
      visit_ids = normalized_visit_ids(grouped_visit_ids.values)
      return {} if names.empty? || visit_ids.empty?
      return {} unless usable_for_visit_ids?(visit_ids)

      grouped_rows = where(visit_id: visit_ids, page_path: names)
        .group(:page_path)
        .pluck(
          :page_path,
          Arel.sql("COALESCE(SUM(legacy_time_on_page_seconds), 0)"),
          Arel.sql("COALESCE(SUM(legacy_time_on_page_count), 0)"),
          Arel.sql("COALESCE(SUM(engaged_seconds_total), 0)"),
          Arel.sql("COUNT(*) FILTER (WHERE has_engagement)"),
          Arel.sql("AVG(CASE WHEN has_engagement THEN max_scroll_depth END)")
        )

      names.each_with_object({}) do |name, result|
        result[name] = metrics_for_page(name, grouped_rows)
      end
    end

    private
      def metrics_for_page(name, grouped_rows)
        row = grouped_rows.find { |page_path, *_rest| page_path == name }
        return { time_on_page: nil, scroll_depth: nil } if row.blank?

        _page_path, legacy_sum, legacy_count, engaged_sum, engagement_visits, average_scroll = row
        denominator = legacy_count.to_i + engagement_visits.to_i

        {
          time_on_page: time_on_page_value(legacy_sum:, legacy_count:, engaged_sum:, engagement_visits:),
          scroll_depth: average_scroll.nil? ? nil : average_scroll.to_f.round
        }
      end

      def time_on_page_value(legacy_sum:, legacy_count:, engaged_sum:, engagement_visits:)
        denominator = legacy_count.to_i + engagement_visits.to_i

        if denominator.positive?
          ((legacy_sum.to_f + engaged_sum.to_f) / denominator.to_f).round(1)
        end
      end

      def build_attributes_for_visit(visit)
        analytics_site_id = visit.analytics_site_id || Analytics::SiteLocator.from_record(visit)&.id
        visitor_token = visit.visitor_token.to_s

        if analytics_site_id.blank? || visitor_token.blank?
          []
        else
          page_metrics = build_page_metrics_for_visit(visit)
          timestamp = Time.current
          started_at = visit.started_at || timestamp

          page_metrics.map do |page_path, metrics|
            {
              visit_id: visit.id,
              analytics_site_id: analytics_site_id,
              started_at: started_at,
              visitor_token: visitor_token,
              page_path: page_path,
              pageviews_count: metrics[:pageviews_count],
              legacy_time_on_page_seconds: metrics[:legacy_time_on_page_seconds],
              legacy_time_on_page_count: metrics[:legacy_time_on_page_count],
              engaged_seconds_total: metrics[:engaged_seconds_total],
              has_engagement: metrics[:has_engagement],
              max_scroll_depth: metrics[:max_scroll_depth],
              created_at: timestamp,
              updated_at: timestamp
            }
          end
        end
      end

      def build_page_metrics_for_visit(visit)
        page_metrics = Hash.new { |hash, key| hash[key] = blank_page_metrics }
        events = ordered_events_for_visit(visit)
        pageviews = ordered_pageviews_for_visit(events)

        pageviews.each do |_time, page_path|
          page_metrics[page_path][:pageviews_count] += 1
        end

        apply_engagement_metrics!(page_metrics, events)
        apply_legacy_time_on_page!(page_metrics, pageviews)

        page_metrics
      end

      def ordered_events_for_visit(visit)
        Analytics::FactStore.ordered_events_for_visit(visit_id: visit.id, site: site_for_visit(visit))
      end

      def ordered_pageviews_for_visit(events)
        events.filter_map do |event|
          next unless event.name == "pageview"

          page_path = event.properties.to_h["page"]
          [ (event.time.respond_to?(:to_time) ? event.time.to_time : event.time), page_label(page_path) ]
        end
      end

      def apply_engagement_metrics!(page_metrics, events)
        events.each do |event|
          next unless event.name == "engagement"

          properties = event.properties.to_h
          label = page_label(properties["page"])
          metrics = page_metrics[label]
          metrics[:engaged_seconds_total] += engaged_seconds(properties["engaged_ms"])
          metrics[:has_engagement] = true
          metrics[:max_scroll_depth] = [ metrics[:max_scroll_depth], parsed_scroll_depth(properties["scroll_depth"]) ].max
        end
      end

      def apply_legacy_time_on_page!(page_metrics, pageviews)
        return if pageviews.length <= 1

        pageviews.each_cons(2) do |(first_time, first_page), (second_time, second_page)|
          next if first_page == second_page
          next if page_metrics[first_page][:has_engagement]

          delta = [ (second_time - first_time).to_f, 0.0 ].max
          page_metrics[first_page][:legacy_time_on_page_seconds] += delta
          page_metrics[first_page][:legacy_time_on_page_count] += 1
        end
      end

      def engaged_seconds(value)
        seconds = value.to_f
        seconds.positive? ? (seconds / 1000.0) : 0.0
      rescue StandardError
        0.0
      end

      def parsed_scroll_depth(value)
        [ value.to_f, 0.0 ].max
      rescue StandardError
        0.0
      end

      def page_label(value)
        normalized = Analytics::Urls.normalized_path_only(value).presence
        normalized || value.to_s.presence || "(unknown)"
      rescue URI::InvalidURIError
        value.to_s.presence || "(unknown)"
      end

      def blank_page_metrics
        {
          pageviews_count: 0,
          legacy_time_on_page_seconds: 0.0,
          legacy_time_on_page_count: 0,
          engaged_seconds_total: 0.0,
          has_engagement: false,
          max_scroll_depth: 0.0
        }
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
        [ "analytics", "visit-page-engagement", visit_id ].join(":")
      end

      def cache_available?
        !Rails.cache.is_a?(ActiveSupport::Cache::NullStore)
      rescue StandardError
        false
      end
  end
end
