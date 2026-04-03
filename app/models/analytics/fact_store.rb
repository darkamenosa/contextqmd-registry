# frozen_string_literal: true

class Analytics::FactStore
  AppendResult = Struct.new(:record, :inserted, keyword_init: true) do
    def inserted?
      inserted == true
    end
  end
  EventFact = Struct.new(:id, :event_id, :visit_id, :name, :time, :properties, keyword_init: true)
  PageviewFact = Struct.new(:visit_id, :time, :page, keyword_init: true)
  PropertyBreakdownFact = Struct.new(:value, :visitors, :events, keyword_init: true)
  VisitFact = Struct.new(
    :id,
    :analytics_site_id,
    :analytics_profile_id,
    :visitor_token,
    :started_at,
    :landing_page,
    :referrer,
    :referring_domain,
    :source_label,
    :source_kind,
    :source_channel,
    :source_favicon_domain,
    :source_paid,
    :country,
    :country_code,
    :region,
    :city,
    :device_type,
    :os,
    :browser,
    :latitude,
    :longitude,
    :user_id,
    :utm_source,
    :utm_medium,
    :utm_campaign,
    keyword_init: true
  ) do
    def analytics_site
      Analytics::Site.find_by(id: analytics_site_id) if analytics_site_id.present?
    end

    def source_paid?
      !!source_paid
    end
  end
  LocationFact = Struct.new(:country_code, :region, :city, :visitors, keyword_init: true)

  class << self
    def append_visit(data:)
      adapter.append_visit(data:)
    end

    def append_event(data:, visit:)
      adapter.append_event(data:, visit:)
    end

    def visit_relation(site: ::Analytics::Current.site_or_default, ids: nil, analytics_profile_ids: nil, started_at_range: nil, with_coordinates: false, order: nil, limit: nil)
      adapter.visit_relation(
        site:,
        ids:,
        analytics_profile_ids:,
        started_at_range:,
        with_coordinates:,
        order:,
        limit:
      )
    end

    def event_relation(site: ::Analytics::Current.site_or_default, range: nil, visit_ids: nil, names: nil, order: nil, limit: nil)
      adapter.event_relation(site:, range:, visit_ids:, names:, order:, limit:)
    end

    def pageview_relation(site: ::Analytics::Current.site_or_default, range: nil, visit_ids: nil, order: nil, limit: nil)
      adapter.pageview_relation(site:, range:, visit_ids:, order:, limit:)
    end

    def visit_by_token(token:, site: ::Analytics::Current.site_or_default)
      adapter.visit_by_token(token:, site:)
    end

    def latest_visit_for_visitor_tokens(visitor_tokens:, started_after:, site: nil)
      adapter.latest_visit_for_visitor_tokens(visitor_tokens:, started_after:, site:)
    end

    def events(site: ::Analytics::Current.site_or_default, range: nil, visit_ids: nil, names: nil, limit: nil, order: :asc)
      adapter.events(site:, range:, visit_ids:, names:, limit:, order:)
    end

    def pageviews(site: ::Analytics::Current.site_or_default, range: nil, visit_ids: nil, limit: nil, order: :asc)
      adapter.pageviews(site:, range:, visit_ids:, limit:, order:)
    end

    def ordered_events_for_visit(visit_id:, site: ::Analytics::Current.site_or_default)
      adapter.ordered_events_for_visit(visit_id:, site:)
    end

    def last_page_for_visit(visit_id:, site: ::Analytics::Current.site_or_default)
      adapter.last_page_for_visit(visit_id:, site:)
    end

    def visits(site: ::Analytics::Current.site_or_default, ids: nil, analytics_profile_ids: nil, started_at_range: nil, with_coordinates: false, order: nil, limit: nil)
      adapter.visits(
        site:,
        ids:,
        analytics_profile_ids:,
        started_at_range:,
        with_coordinates:,
        order:,
        limit:
      )
    end

    def visit(visit_id:, site: ::Analytics::Current.site_or_default, analytics_profile_id: nil)
      adapter.visit(visit_id:, site:, analytics_profile_id:)
    end

    def visit_counts_by_profile(site: ::Analytics::Current.site_or_default, profile_ids:)
      adapter.visit_counts_by_profile(site:, profile_ids:)
    end

    def active_visits(site: ::Analytics::Current.site_or_default, now:, window:, with_coordinates: false)
      adapter.active_visits(site:, now:, window:, with_coordinates:)
    end

    def live_visitors_count(site: ::Analytics::Current.site_or_default, now:, window:)
      adapter.live_visitors_count(site:, now:, window:)
    end

    def latest_event_times_by_visit_id(site: ::Analytics::Current.site_or_default, visit_ids:, since:)
      adapter.latest_event_times_by_visit_id(site:, visit_ids:, since:)
    end

    def sessions_by_location(site: ::Analytics::Current.site_or_default, range:, limit:)
      adapter.sessions_by_location(site:, range:, limit:)
    end

    def visit_series_counts(site: ::Analytics::Current.site_or_default, start_at:, buckets:, bucket_seconds:)
      adapter.visit_series_counts(site:, start_at:, buckets:, bucket_seconds:)
    end

    def non_pageview_visit_ids(site: ::Analytics::Current.site_or_default, visit_ids:)
      adapter.non_pageview_visit_ids(site:, visit_ids:)
    end

    def visit_ids_matching_page(site: ::Analytics::Current.site_or_default, visit_ids:, range: nil, operator:, value:)
      adapter.visit_ids_matching_page(site:, visit_ids:, range:, operator:, value:)
    end

    def visit_ids_matching_property(site: ::Analytics::Current.site_or_default, visit_ids:, property:, operator:, value:)
      adapter.visit_ids_matching_property(site:, visit_ids:, property:, operator:, value:)
    end

    def property_keys(site: ::Analytics::Current.site_or_default, range: nil, visit_ids: nil, names: nil, exclude_names: nil, goal: nil, limit: nil)
      adapter.property_keys(site:, range:, visit_ids:, names:, exclude_names:, goal:, limit:)
    end

    def property_breakdown(site: ::Analytics::Current.site_or_default, range:, visit_ids:, property:, names: nil, exclude_names: nil, goal: nil, property_filters: [], search: nil)
      adapter.property_breakdown(
        site:,
        range:,
        visit_ids:,
        property:,
        names:,
        exclude_names:,
        goal:,
        property_filters:,
        search:
      )
    end

    def distinct_property_visitor_count(site: ::Analytics::Current.site_or_default, range:, visit_ids:, property:, names: nil, exclude_names: nil, goal: nil, property_filters: [])
      adapter.distinct_property_visitor_count(
        site:,
        range:,
        visit_ids:,
        property:,
        names:,
        exclude_names:,
        goal:,
        property_filters:
      )
    end

    def goal_event_totals(site: ::Analytics::Current.site_or_default, range:, visit_ids:, goal_name:, goal: nil)
      adapter.goal_event_totals(site:, range:, visit_ids:, goal_name:, goal:)
    end

    def goal_event_visit_ids(site: ::Analytics::Current.site_or_default, range:, visit_ids:, goal_name:, goal: nil)
      adapter.goal_event_visit_ids(site:, range:, visit_ids:, goal_name:, goal:)
    end

    def goal_event_bucket_counts(site: ::Analytics::Current.site_or_default, range:, visit_ids:, goal_name:, goal: nil, interval:)
      adapter.goal_event_bucket_counts(site:, range:, visit_ids:, goal_name:, goal:, interval:)
    end

    def event_totals_for_bucket(site: ::Analytics::Current.site_or_default, bucket_start:)
      adapter.event_totals_for_bucket(site:, bucket_start:)
    end

    def visit_totals_for_bucket(site: ::Analytics::Current.site_or_default, bucket_start:)
      adapter.visit_totals_for_bucket(site:, bucket_start:)
    end

    def raw_visit_metric_totals(site: ::Analytics::Current.site_or_default, visit_ids:)
      adapter.raw_visit_metric_totals(site:, visit_ids:)
    end

    def page_rollup_rows(site: ::Analytics::Current.site_or_default, bucket_start:)
      adapter.page_rollup_rows(site:, bucket_start:)
    end

    def source_rollup_rows(site: ::Analytics::Current.site_or_default, bucket_start:)
      adapter.source_rollup_rows(site:, bucket_start:)
    end

    def location_rollup_rows(site: ::Analytics::Current.site_or_default, bucket_start:)
      adapter.location_rollup_rows(site:, bucket_start:)
    end

    private
      def adapter
        @adapter ||= adapter_class.new
      end

      def adapter_class
        case Analytics::Configuration.storage.to_s
        when "postgres"
          Analytics::FactStore::Postgres
        else
          raise NotImplementedError, "Unsupported analytics fact store: #{Analytics::Configuration.storage}"
        end
      end
  end
end
