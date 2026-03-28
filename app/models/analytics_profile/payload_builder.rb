# frozen_string_literal: true

require "uri"
require "set"
require "cgi"
require Rails.root.join("lib/analytics/country")

module AnalyticsProfile::PayloadBuilder
  private
    def build_live_session_row(profile, visit:, recent_events:, total_visits:, active:, last_seen_at:)
      live_events = dedupe_live_events(
        recent_events.map do |event|
          build_live_event(
            event,
            profile,
            visit,
            total_visits: total_visits,
            active: active,
            last_seen_at: last_seen_at
          )
        end
      )

      build_live_session_snapshot(
        profile,
        visit,
        total_visits: total_visits,
        active: active,
        last_seen_at: last_seen_at
      ).merge(
        recent_events: live_events.reject { |event| event[:event_name] == "engagement" }.first(15)
      )
    end

    def build_profile_row(profile, latest_visit:, last_seen_at:, total_visits:, scoped_visits:, summary: nil)
      identity_snapshot = resolved_identity_snapshot(profile, latest_visit)
      latest_context = summary&.latest_context.to_h
      current_page = summary&.latest_current_page.presence || latest_context["current_page"].presence || current_page_for_visit(latest_visit)
      resolved_country = Analytics::Country.resolve(
        country: summary&.latest_country_name.presence || latest_context["country"].presence || latest_visit&.country,
        country_code: summary&.latest_country_code.presence || latest_context["country_code"].presence || latest_visit&.try(:country_code)
      )
      city = summary&.latest_city.presence || latest_context["city"].presence || latest_visit&.city.to_s.presence
      region = summary&.latest_region.presence || latest_context["region"].presence || latest_visit&.region.to_s.presence
      country = resolved_country.name
      serialized_locations_used = Array(summary&.locations_used).map { |item| serialize_location(item.to_h) }

      {
        id: profile.public_id,
        public_id: profile.public_id,
        name: summary&.display_name.presence || display_name_for(profile, identity_snapshot),
        status: profile.status,
        identified: profile.status == AnalyticsProfile::STATUS_IDENTIFIED,
        email: summary&.email.presence || email_for(profile, identity_snapshot),
        first_seen_at: (summary&.first_seen_at || profile.first_seen_at)&.iso8601,
        country: country,
        country_code: resolved_country.code,
        city: city,
        region: region,
        location_label: Analytics::Locations.location_label(city:, region:, country:),
        device_type: summary&.latest_device_type.presence || latest_context["device_type"].presence || latest_visit&.device_type.to_s.presence || "Desktop",
        os: summary&.latest_os.presence || latest_context["os"].presence || latest_visit&.os.to_s.presence,
        browser: summary&.latest_browser.presence || latest_context["browser"].presence || latest_visit&.browser.to_s.presence,
        source: summary&.latest_source.presence || latest_context["source"].presence || latest_visit&.source_label.to_s.presence || latest_visit&.referring_domain.to_s.presence || "Direct / None",
        current_page: current_page,
        last_seen_at: last_seen_at&.iso8601,
        total_visits: total_visits,
        scoped_visits: scoped_visits,
        total_sessions: summary&.total_sessions || total_visits,
        total_pageviews: summary&.total_pageviews || 0,
        total_events: summary&.total_events || 0,
        latest_context: latest_context,
        devices_used: summary&.devices_used || [],
        browsers_used: summary&.browsers_used || [],
        oses_used: summary&.oses_used || [],
        sources_used: summary&.sources_used || [],
        locations_used: serialized_locations_used,
        top_pages: summary&.top_pages || []
      }
    end

    def build_live_session_snapshot(profile, visit, total_visits:, active:, last_seen_at:)
      build_profile_row(
        profile,
        latest_visit: visit,
        last_seen_at: last_seen_at || visit&.started_at || profile.last_seen_at,
        total_visits: total_visits,
        scoped_visits: 1
      ).merge(
        id: visit.id.to_s,
        session_id: visit.id.to_s,
        visit_id: visit.id,
        active: active,
        started_at: visit.started_at&.iso8601,
        last_seen_at: (last_seen_at || visit.started_at)&.iso8601,
        lat: visit.latitude&.to_f,
        lng: visit.longitude&.to_f
      )
    end

    def build_live_event(event, profile, visit, total_visits:, active:, last_seen_at:)
      props = event.properties.to_h.with_indifferent_access
      page = props[:page].presence || current_page_for_visit(visit)
      build_live_session_snapshot(
        profile,
        visit,
        total_visits: total_visits,
        active: active,
        last_seen_at: last_seen_at
      ).merge(
        id: event.id,
        event_name: event.name,
        label: event_label_for(event, page),
        occurred_at: event.time.iso8601,
        page: page
      )
    end

    def build_journey_event(event, visit)
      props = event.properties.to_h.with_indifferent_access
      page = props[:page].presence || current_page_for_visit(visit)

      {
        id: event.id,
        visit_id: visit&.id,
        event_name: event.name,
        label: event_label_for(event, page),
        occurred_at: event.time.iso8601,
        page: page,
        properties: props.except(:page, :url, :title, :referrer, :screen_size)
      }
    end

    def event_label_for(event, page)
      if event.name == "pageview"
        "Viewed page #{page || '/'}"
      else
        [ event.name.to_s, page.present? ? "on #{page}" : nil ].compact.join(" ")
      end
    end

    def dedupe_live_events(events)
      seen = Set.new

      events.each_with_object([]) do |event, rows|
        key = [ event[:session_id], event[:label], event[:page] ]
        next if seen.include?(key)

        seen << key
        rows << event
      end
    end

    def current_page_for_visit(visit)
      return unless visit

      pageview = Ahoy::Event
        .where(visit_id: visit.id, name: "pageview")
        .order(time: :desc, id: :desc)
        .limit(1)
        .pick(Arel.sql("ahoy_events.properties->>'page'"))

      return pageview if pageview.present?

      normalized_path(visit.landing_page)
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

    def resolved_identity_snapshot(profile, visit)
      identity =
        if visit&.user_id.present?
          Identity.find_by(id: visit.user_id)
        else
          identity_key = profile.profile_keys.find { |key| key.kind == "identity_id" }
          identity_key&.value.present? ? Identity.find_by(id: identity_key.value) : nil
        end

      return nil if identity.blank?

      {
        display_name: identity.display_name,
        email: identity.email
      }
    rescue StandardError
      nil
    end

    def display_name_for(profile, identity_snapshot)
      profile.traits.to_h["display_name"].presence ||
        identity_snapshot&.dig(:display_name).presence ||
        profile.display_name
    end

    def email_for(profile, identity_snapshot)
      profile.traits.to_h["email"].presence || identity_snapshot&.dig(:email).presence
    end

    def profile_sessions_payload(profile, visits)
      visit_ids = visits.map(&:id)
      return [] if visit_ids.empty?
      return [] unless AnalyticsProfile::Projection.available?

      AnalyticsProfileSession
        .where(analytics_profile_id: profile.id, visit_id: visit_ids)
        .order(started_at: :desc, id: :desc)
        .map { |session| serialize_session(session) }
    end

    def profile_activity_payload(profile)
      return [] unless AnalyticsProfile::Projection.available?

      AnalyticsProfileSession
        .where(analytics_profile_id: profile.id)
        .order(started_at: :desc, id: :desc)
        .pluck(:started_at, :events_count)
        .map do |started_at, events_count|
          {
            started_at: started_at&.iso8601,
            count: events_count.to_i
          }
        end
    end

    def serialize_session(session)
      resolved_country = Analytics::Country.resolve(
        country: session.country,
        country_code: session.respond_to?(:country_code) ? session.country_code : nil
      )
      country = resolved_country.name
      city = session.city
      region = session.region

      {
        id: session.visit_id,
        visit_id: session.visit_id,
        started_at: session.started_at&.iso8601,
        last_event_at: session.last_event_at&.iso8601,
        country: country,
        country_code: resolved_country.code,
        region: region,
        city: city,
        location_label: Analytics::Locations.location_label(city:, region:, country:),
        device_type: session.device_type,
        os: session.os,
        browser: session.browser,
        source: session.source,
        entry_page: session.entry_page,
        exit_page: session.exit_page,
        current_page: session.current_page,
        duration_seconds: session.duration_seconds,
        pageviews_count: session.pageviews_count,
        events_count: session.events_count,
        page_paths: session.page_paths,
        event_names: session.event_names
      }
    end

    def serialize_location(location)
      resolved_country = Analytics::Country.resolve(
        country: location["country"],
        country_code: location["country_code"]
      )
      region = location["region"].to_s.presence
      city = location["city"].to_s.presence
      country_name = resolved_country.name

      {
        "label" => Analytics::Locations.location_label(
          city: city,
          region: region,
          country: country_name
        ),
        "count" => location["count"].to_i,
        "country" => country_name,
        "country_code" => resolved_country.code,
        "region" => region,
        "city" => city,
        "last_seen_at" => location["last_seen_at"]
      }.compact
    end

    def build_session_source_summary(visit)
      source_label = visit.source_label.to_s.presence || "Direct / None"
      {
        source_label: source_label,
        source_kind: visit.source_kind.to_s.presence,
        source_channel: visit.source_channel.to_s.presence,
        favicon_domain: visit.source_favicon_domain.to_s.presence,
        referring_domain: visit.referring_domain.to_s.presence,
        referrer: visit.referrer.to_s.presence,
        landing_page: normalized_path(visit.landing_page),
        utm_source: visit.utm_source.to_s.presence,
        utm_medium: visit.utm_medium.to_s.presence,
        utm_campaign: visit.utm_campaign.to_s.presence,
        tracker_params: tracker_params_for_visit(visit),
        search_terms: search_terms_for_visit(visit)
      }
    end

    def filtered_session_events(visit_id, query)
      query = Analytics::Query.wrap(query)
      events = Ahoy::Event.where(visit_id: visit_id).order(time: :desc, id: :desc).limit(200).to_a
      page_filter = query.filter_value(:page).presence
      goal_filter = query.filter_value(:goal).presence
      page_filter_clauses = query.filter_clauses.select { |_op, dim, _value| dim == :page }

      events = events.select do |event|
        props = event.properties.to_h.with_indifferent_access
        page = props[:page].presence

        matches_page =
          if page_filter.present?
            page == page_filter
          else
            true
          end

        matches_goal =
          if goal_filter.present?
            event.name == goal_filter
          else
            true
          end

        matches_advanced = page_filter_clauses.all? do |(op, _dim, clause)|
          case op
          when :not_eq
            page != clause
          when :contains
            page.to_s.include?(clause.to_s)
          when :eq
            page == clause
          else
            true
          end
        end

        matches_page && matches_goal && matches_advanced
      end

      events.reject! { |event| event.name.to_s == "engagement" }
      events
    end

    def tracker_params_for_visit(visit)
      uri = URI.parse(visit.landing_page.to_s)
      return [] if uri.query.blank?

      CGI.parse(uri.query).each_with_object([]) do |(key, values), rows|
        next unless tracker_param_key?(key)

        value = Array(values).first.to_s.presence
        next if value.blank?

        rows << { key: key, value: value }
      end.first(4)
    rescue URI::InvalidURIError
      []
    end

    def tracker_param_key?(key)
      candidate = key.to_s.downcase
      return false if candidate.start_with?("utm_")

      %w[ref via coupon code invite source tracker trk campaign].include?(candidate)
    end

    def search_terms_for_visit(visit)
      query = search_query_from_referrer(visit.referrer)
      return [] if query.blank?

      build_search_term_preview(query)
    end

    def search_query_from_referrer(referrer)
      return if referrer.blank?

      uri = URI.parse(referrer.to_s)
      params = CGI.parse(uri.query.to_s)
      %w[q query p text keyword k].each do |key|
        value = Array(params[key]).first.to_s.strip
        return value if value.present?
      end

      nil
    rescue URI::InvalidURIError
      nil
    end

    def build_search_term_preview(query)
      terms = query.to_s.split(/\s+/).reject(&:blank?)
      return [] if terms.empty?

      rows = [ { "label" => query, "probability" => 74 } ]

      if terms.length > 1
        rows << {
          "label" => terms.first(2).join(" "),
          "probability" => 16
        }
        rows << {
          "label" => terms.last,
          "probability" => 10
        }
      end

      rows.uniq { |row| row["label"].downcase }
    end

    def dedupe_session_events(events)
      last_key = nil

      events.each_with_object([]) do |event, rows|
        key = [ event[:label], event[:page] ]
        next if key == last_key

        rows << event
        last_key = key
      end
    end
end
