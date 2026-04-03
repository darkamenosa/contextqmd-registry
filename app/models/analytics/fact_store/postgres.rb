# frozen_string_literal: true

require "set"

class Analytics::FactStore::Postgres
  EVENT_COLUMNS = %i[event_id name properties time user_id analytics_site_id analytics_site_boundary_id].freeze
  VISIT_COLUMNS = %i[
    id
    analytics_site_id
    analytics_profile_id
    visitor_token
    started_at
    landing_page
    referrer
    referring_domain
    source_label
    source_kind
    source_channel
    source_favicon_domain
    source_paid
    country
    country_code
    region
    city
    device_type
    os
    browser
    latitude
    longitude
    user_id
    utm_source
    utm_medium
    utm_campaign
  ].freeze

  def append_visit(data:)
    attrs = slice_model_data(Ahoy::Visit, data)
    visit = Ahoy::Visit.create!(attrs)

    Analytics::FactStore::AppendResult.new(record: visit, inserted: true)
  rescue StandardError => error
    raise error unless unique_exception?(error)

    Analytics::FactStore::AppendResult.new(
      record: attrs[:visit_token].present? ? visit_by_token(token: attrs[:visit_token], site: nil) : nil,
      inserted: false
    )
  end

  def append_event(data:, visit:)
    attrs = slice_model_data(Ahoy::Event, data)
    event = Ahoy::Event.new(attrs)
    event.visit = visit
    event.analytics_site_id ||= visit.analytics_site_id if event.respond_to?(:analytics_site_id)
    if event.respond_to?(:analytics_site_boundary_id)
      event.analytics_site_boundary_id ||= visit.analytics_site_boundary_id
    end
    event.time = visit.started_at if event.time.present? && visit.started_at.present? && event.time < visit.started_at
    event.save!

    Analytics::FactStore::AppendResult.new(record: event, inserted: true)
  rescue StandardError => error
    raise error unless unique_exception?(error)

    Analytics::FactStore::AppendResult.new(
      record: attrs[:event_id].present? ? event_by_event_id(event_id: attrs[:event_id], site: nil) : nil,
      inserted: false
    )
  end

  def visit_relation(site:, ids: nil, analytics_profile_ids: nil, started_at_range: nil, with_coordinates: false, order: nil, limit: nil)
    scope = Ahoy::Visit.for_analytics_site(site)
    scope = scope.where(id: ids) if ids.present?
    scope = scope.where(analytics_profile_id: analytics_profile_ids) if analytics_profile_ids.present?
    scope = scope.where(started_at: started_at_range) if started_at_range.present?
    scope = scope.with_coordinates if with_coordinates
    scope = apply_visit_order(scope, order) if order.present?
    scope = scope.limit(limit) if limit.present?
    scope
  end

  def event_relation(site:, range: nil, visit_ids: nil, names: nil, order: nil, limit: nil)
    scope = Ahoy::Event.for_analytics_site(site)
    scope = scope.where(time: range) if range.present?
    scope = scope.where(visit_id: visit_ids) if visit_ids.present?
    scope = scope.where(name: names) if names.present?
    scope = apply_event_order(scope, order) if order.present?
    scope = scope.limit(limit) if limit.present?
    scope
  end

  def pageview_relation(site:, range: nil, visit_ids: nil, order: nil, limit: nil)
    event_relation(site:, range:, visit_ids:, names: [ "pageview" ], order:, limit:)
  end

  def visit_by_token(token:, site:)
    return if token.blank?

    scope = Ahoy::Visit.where(visit_token: token)
    scope = Analytics::Scope.apply(scope, site:) if site.present?
    scope.take
  end

  def latest_visit_for_visitor_tokens(visitor_tokens:, started_after:, site:)
    tokens = Array(visitor_tokens).compact
    return if tokens.empty? || started_after.blank?

    scope = Ahoy::Visit.where(visitor_token: tokens, started_at: started_after..)
    scope = Analytics::Scope.apply(scope, site:) if site.present?
    scope.order(started_at: :desc, id: :desc).first
  end

  def events(site:, range: nil, visit_ids: nil, names: nil, limit: nil, order: :asc)
    scope = event_relation(site:, range:, visit_ids:, names:, limit:, order: nil)
    scope = apply_event_order(scope, order || :asc)

    scope.pluck(:id, :event_id, :visit_id, :name, :time, :properties).map do |id, event_id, visit_id, name, time, properties|
      Analytics::FactStore::EventFact.new(
        id: id,
        event_id: event_id.to_s.presence,
        visit_id: visit_id,
        name: name.to_s,
        time: time.respond_to?(:to_time) ? time.to_time : time,
        properties: properties.to_h
      )
    end
  end

  def pageviews(site:, range: nil, visit_ids: nil, limit: nil, order: :asc)
    scope = pageview_relation(site:, range:, visit_ids:, limit:, order: nil)
    scope = apply_event_order(scope, order || :asc)

    scope.pluck(:visit_id, :time, Arel.sql("COALESCE(ahoy_events.properties->>'page', '')")).map do |visit_id, time, page|
      Analytics::FactStore::PageviewFact.new(
        visit_id: visit_id,
        time: time.respond_to?(:to_time) ? time.to_time : time,
        page: page.to_s
      )
    end
  end

  def ordered_events_for_visit(visit_id:, site:)
    events(site:, visit_ids: [ visit_id ], order: :asc)
  end

  def last_page_for_visit(visit_id:, site:)
    Ahoy::Event
      .for_analytics_site(site)
      .where(visit_id:, name: "pageview")
      .order(time: :desc, id: :desc)
      .limit(1)
      .pick(Arel.sql("ahoy_events.properties->>'page'"))
      .to_s
      .presence
  end

  def visits(site:, ids: nil, analytics_profile_ids: nil, started_at_range: nil, with_coordinates: false, order: nil, limit: nil)
    scope = visit_relation(
      site:,
      ids:,
      analytics_profile_ids:,
      started_at_range:,
      with_coordinates:,
      order: nil,
      limit:
    )
    scope = apply_visit_order(scope, order)

    scope.pluck(*VISIT_COLUMNS).map do |values|
      Analytics::FactStore::VisitFact.new(**VISIT_COLUMNS.zip(values).to_h)
    end
  end

  def visit(visit_id:, site:, analytics_profile_id:)
    scope = Ahoy::Visit.for_analytics_site(site).where(id: visit_id)
    scope = scope.where(analytics_profile_id:) if analytics_profile_id.present?

    values = scope.limit(1).pluck(*VISIT_COLUMNS).first
    if values.present?
      Analytics::FactStore::VisitFact.new(**VISIT_COLUMNS.zip(values).to_h)
    end
  end

  def visit_counts_by_profile(site:, profile_ids:)
    return {} if Array(profile_ids).compact.empty?

    Ahoy::Visit.for_analytics_site(site).where(analytics_profile_id: profile_ids).group(:analytics_profile_id).count
  end

  def active_visits(site:, now:, window:, with_coordinates:)
    window_start = now - window
    recent_visit_ids = recent_event_visit_ids(site:, since: window_start)
    started_range = window_start..now
    scope_ids = Ahoy::Visit.for_analytics_site(site).where(started_at: started_range).pluck(:id)
    ids = (scope_ids + recent_visit_ids).uniq

    if ids.any?
      visits(
        site:,
        ids: ids,
        with_coordinates: with_coordinates,
        order: { started_at: :desc, id: :desc }
      )
    else
      []
    end
  end

  def live_visitors_count(site:, now:, window:)
    cutoff = now - window
    recent_visit_ids = recent_event_visit_ids(site:, since: cutoff)
    started_visit_ids = Ahoy::Visit.for_analytics_site(site).where(started_at: cutoff..now).pluck(:id)
    active_visit_ids = (started_visit_ids + recent_visit_ids).uniq

    if active_visit_ids.any?
      Ahoy::Visit.for_analytics_site(site).where(id: active_visit_ids).distinct.count(:visitor_token)
    else
      0
    end
  end

  def latest_event_times_by_visit_id(site:, visit_ids:, since:)
    return {} if Array(visit_ids).compact.empty?

    Ahoy::Event
      .for_analytics_site(site)
      .where(visit_id: visit_ids)
      .where("time >= ?", since)
      .group(:visit_id)
      .maximum(:time)
      .transform_values { |time| time.respond_to?(:to_time) ? time.to_time : time }
  end

  def sessions_by_location(site:, range:, limit:)
    Ahoy::Visit
      .for_analytics_site(site)
      .where(started_at: range)
      .group(:country_code, :region, :city)
      .order(Arel.sql("COUNT(*) DESC"))
      .limit(limit)
      .count
      .map do |(country_code, region, city), visitors|
        Analytics::FactStore::LocationFact.new(
          country_code: country_code.to_s.presence,
          region: region.to_s.presence,
          city: city.to_s.presence,
          visitors: visitors.to_i
        )
      end
  end

  def visit_series_counts(site:, start_at:, buckets:, bucket_seconds:)
    finish = start_at + (buckets - 1) * bucket_seconds
    seconds = bucket_seconds.to_i.clamp(1, 86_400)
    connection = Ahoy::Visit.connection
    site_id = Analytics::Site === site ? site.id : site.presence
    sql = Ahoy::Visit.send(
      :sanitize_sql_array,
      [
        <<~SQL.squish,
      WITH series AS (
        SELECT generate_series(
          CAST(? AS timestamptz),
          CAST(? AS timestamptz),
          make_interval(secs => CAST(? AS integer))
        ) AS bucket
      )
      SELECT
        s.bucket AS bucket,
        COUNT(visits.id) AS value
      FROM series s
      LEFT JOIN ahoy_visits visits
        ON visits.started_at >= s.bucket
       AND visits.started_at < s.bucket + make_interval(secs => CAST(? AS integer))
       AND (CAST(? AS bigint) IS NULL OR visits.analytics_site_id = CAST(? AS bigint))
      GROUP BY s.bucket
      ORDER BY s.bucket ASC
        SQL
        start_at.utc.iso8601,
        finish.utc.iso8601,
        seconds,
        seconds,
        site_id,
        site_id
      ]
    )

    connection.exec_query(sql).rows.map { |(_, value)| value.to_i }
  end

  def non_pageview_visit_ids(site:, visit_ids:)
    return Set.new if Array(visit_ids).compact.empty?

    Ahoy::Event
      .for_analytics_site(site)
      .where(visit_id: visit_ids)
      .where.not(name: "pageview")
      .distinct
      .pluck(:visit_id)
      .to_set
  end

  def visit_ids_matching_page(site:, visit_ids:, range:, operator:, value:)
    return [] if value.to_s.strip.empty?

    scope = Ahoy::Event.for_analytics_site(site).where(name: "pageview")
    scope = scope.where(time: range) if range.present?
    scope = scope.where(visit_id: visit_ids)

    case operator.to_s
    when "contains"
      scope = scope.where("LOWER(COALESCE(ahoy_events.properties->>'page', '')) LIKE ?", Analytics::Search.contains_pattern(value))
    else
      scope = scope.where(Arel.sql("ahoy_events.properties->>'page' = ?"), value.to_s)
    end

    scope.distinct.pluck(:visit_id)
  end

  def visit_ids_matching_property(site:, visit_ids:, property:, operator:, value:)
    property_name = property.to_s.strip
    return [] if property_name.blank? || value.to_s.strip.empty?

    quoted_property = Ahoy::Event.connection.quote(property_name)
    value_expr = "COALESCE(NULLIF(ahoy_events.properties->>#{quoted_property}, ''), '(none)')"
    scope = Ahoy::Event
      .for_analytics_site(site)
      .where(visit_id: visit_ids)
      .where(Arel.sql("ahoy_events.properties ? #{quoted_property}"))

    case operator.to_s
    when "contains"
      scope = scope.where("LOWER(#{value_expr}) LIKE ?", Analytics::Search.contains_pattern(value))
    else
      scope = scope.where(Arel.sql("#{value_expr} = ?"), value.to_s)
    end

    scope.distinct.pluck(:visit_id)
  end

  def property_keys(site:, range: nil, visit_ids: nil, names: nil, exclude_names: nil, goal: nil, limit: nil)
    scope = property_scope(site:, range:, visit_ids:, names:, exclude_names:, goal:)
    return [] unless scope.exists?

    keys_relation = Ahoy::Event.unscoped.from(scope.select("jsonb_object_keys(ahoy_events.properties) AS key"), :property_keys).select(:key).distinct
    keys_relation = keys_relation.limit(limit.to_i.clamp(1, 1_000)) if limit.present?
    keys_relation.pluck(:key).map(&:to_s)
  end

  def property_breakdown(site:, range:, visit_ids:, property:, names: nil, exclude_names: nil, goal: nil, property_filters: [], search: nil)
    property_name = property.to_s.strip
    return [] if property_name.blank?

    scope = property_scope(site:, range:, visit_ids:, names:, exclude_names:, goal:)
    scope = scope.where(Analytics::Properties.event_property_exists(property_name))
    scope = apply_property_filters(scope, property_filters)

    value_expr = Analytics::Properties.event_property_value(property_name)
    if search.present?
      scope = scope.where(Analytics::Properties.event_property_value_lower(property_name).matches(Analytics::Search.contains_pattern(search)))
    end

    scope
      .group(value_expr)
      .pluck(
        value_expr,
        Arel.sql("COUNT(DISTINCT ahoy_visits.visitor_token)"),
        Arel.sql("COUNT(*)")
      )
      .map do |value, visitors, events|
        Analytics::FactStore::PropertyBreakdownFact.new(
          value: value.to_s,
          visitors: visitors.to_i,
          events: events.to_i
        )
      end
  end

  def distinct_property_visitor_count(site:, range:, visit_ids:, property:, names: nil, exclude_names: nil, goal: nil, property_filters: [])
    property_name = property.to_s.strip
    return 0 if property_name.blank?

    scope = property_scope(site:, range:, visit_ids:, names:, exclude_names:, goal:)
    scope = scope.where(Analytics::Properties.event_property_exists(property_name))
    scope = apply_property_filters(scope, property_filters)
    scope.distinct.count("ahoy_visits.visitor_token")
  end

  def goal_event_totals(site:, range:, visit_ids:, goal_name:, goal:)
    scope = goal_event_scope(site:, range:, visit_ids:, goal_name:, goal:)
    return { unique_conversions: 0, total_conversions: 0 } if scope.none?

    {
      unique_conversions: scope.distinct.count("ahoy_visits.visitor_token"),
      total_conversions: scope.count
    }
  end

  def goal_event_visit_ids(site:, range:, visit_ids:, goal_name:, goal:)
    goal_event_scope(site:, range:, visit_ids:, goal_name:, goal:).distinct.pluck(:visit_id)
  end

  def goal_event_bucket_counts(site:, range:, visit_ids:, goal_name:, goal:, interval:)
    grouped_expression = Analytics::Ranges.bucket_sql_for("time", interval)

    goal_event_scope(site:, range:, visit_ids:, goal_name:, goal:)
      .group(Arel.sql(grouped_expression))
      .count
      .each_with_object({}) do |(bucket_time, value), result|
        key = bucket_time.is_a?(Time) ? bucket_time.utc : bucket_time.to_time.utc
        result[key] = value.to_i
      end
  end

  def event_totals_for_bucket(site:, bucket_start:)
    bucket = normalize_bucket_start(bucket_start)
    return { events_count: 0, pageviews_count: 0 } if bucket.blank?

    scope = Ahoy::Event.for_analytics_site(site).where(time: bucket...(bucket + 1.hour))
    {
      events_count: scope.count,
      pageviews_count: scope.where(name: "pageview").count
    }
  end

  def visit_totals_for_bucket(site:, bucket_start:)
    bucket = normalize_bucket_start(bucket_start)
    return { visits_count: 0, unique_visitors_count: 0, visit_ids: [] } if bucket.blank?

    scope = Ahoy::Visit.for_analytics_site(site).where(started_at: bucket...(bucket + 1.hour))
    visit_ids = scope.pluck(:id)

    {
      visits_count: visit_ids.size,
      unique_visitors_count: scope.distinct.count(:visitor_token),
      visit_ids: visit_ids
    }
  end

  def raw_visit_metric_totals(site:, visit_ids:)
    ids = Array(visit_ids).compact
    return [ 0, 0, 0.0 ] if ids.empty?

    event_table = Ahoy::Event.table_name
    pageview_stats = Ahoy::Event
      .for_analytics_site(site)
      .where(visit_id: ids, name: "pageview")
      .group("#{event_table}.visit_id")
      .pluck(
        Arel.sql("#{event_table}.visit_id"),
        Arel.sql("COUNT(*)"),
        Arel.sql("GREATEST(EXTRACT(EPOCH FROM (MAX(#{event_table}.time) - MIN(#{event_table}.time))), 0)")
      )

    pageviews_count = 0
    total_visit_duration_seconds = 0.0
    bounce_candidates = {}

    pageview_stats.each do |visit_id, pageviews, duration_seconds|
      pageviews_count += pageviews.to_i
      total_visit_duration_seconds += duration_seconds.to_f
      bounce_candidates[visit_id] = pageviews.to_i
    end

    non_pageview_ids = non_pageview_visit_ids(site:, visit_ids: ids)
    bounces_count = bounce_candidates.count do |visit_id, pageviews|
      pageviews == 1 && !non_pageview_ids.include?(visit_id)
    end

    [ pageviews_count, bounces_count, total_visit_duration_seconds ]
  end

  def page_rollup_rows(site:, bucket_start:)
    bucket = normalize_bucket_start(bucket_start)
    return [] if bucket.blank?

    scope = Ahoy::Event
      .for_analytics_site(site)
      .where(name: "pageview", time: bucket...(bucket + 1.hour))
      .joins(:visit)

    grouped = scope.group(Arel.sql(page_rollup_expression), "ahoy_visits.visitor_token").count
    return [] if grouped.empty?

    now = Time.current
    grouped.each_with_object([]) do |((page_path, visitor_token), pageviews_count), rows|
      next if visitor_token.blank?

      rows << {
        analytics_site_id: normalize_site_id(site),
        bucket_start: bucket,
        page_path: page_path.to_s,
        visitor_token: visitor_token,
        pageviews_count: pageviews_count.to_i,
        created_at: now,
        updated_at: now
      }
    end
  end

  def source_rollup_rows(site:, bucket_start:)
    bucket = normalize_bucket_start(bucket_start)
    return [] if bucket.blank?

    rows = Ahoy::Visit
      .for_analytics_site(site)
      .where(started_at: bucket...(bucket + 1.hour))
      .distinct
      .pluck(
        :visitor_token,
        Arel.sql(Analytics::Sources.mode_sql("all").first),
        Arel.sql(Analytics::Sources.mode_sql("channels").first),
        Arel.sql(Analytics::Sources.mode_sql("referrers").first),
        Arel.sql(Analytics::Sources.mode_sql("utm-medium").first),
        Arel.sql("COALESCE(utm_source, '')"),
        Arel.sql("COALESCE(utm_campaign, '')"),
        Arel.sql("COALESCE(utm_content, '')"),
        Arel.sql("COALESCE(utm_term, '')")
      )
    return [] if rows.empty?

    now = Time.current
    deduped = {}

    rows.each do |visitor_token, *values|
      next if visitor_token.blank?

      Analytics::SiteSourceHourlyVisitorRollup::ROLLUP_DIMENSIONS.zip(values).each do |dimension, value|
        normalized_value = value.to_s
        next if Analytics::SiteSourceHourlyVisitorRollup::SPARSE_DIMENSIONS.include?(dimension) && normalized_value.blank?

        key = [ dimension, normalized_value, visitor_token ]
        deduped[key] ||= {
          analytics_site_id: normalize_site_id(site),
          bucket_start: bucket,
          dimension: dimension,
          value: normalized_value,
          visitor_token: visitor_token,
          created_at: now,
          updated_at: now
        }
      end
    end

    deduped.values
  end

  def location_rollup_rows(site:, bucket_start:)
    bucket = normalize_bucket_start(bucket_start)
    return [] if bucket.blank?

    rows = Ahoy::Visit
      .for_analytics_site(site)
      .where(started_at: bucket...(bucket + 1.hour))
      .distinct
      .pluck(
        :visitor_token,
        Arel.sql("COALESCE(NULLIF(country_code, ''), '(unknown)')"),
        Arel.sql("COALESCE(region, '(unknown)')"),
        Arel.sql("COALESCE(city, '(unknown)')"),
        Arel.sql("COALESCE(NULLIF(country_code, ''), '')")
      )
    return [] if rows.empty?

    now = Time.current
    deduped = {}

    rows.each do |visitor_token, country_value, region_value, city_value, country_code|
      next if visitor_token.blank?

      add_location_rollup_row!(
        deduped,
        site_id: normalize_site_id(site),
        bucket_start: bucket,
        dimension: "countries",
        value: country_value.to_s,
        country_code: country_code.to_s,
        visitor_token: visitor_token,
        now: now
      )
      add_location_rollup_row!(
        deduped,
        site_id: normalize_site_id(site),
        bucket_start: bucket,
        dimension: "regions",
        value: region_value.to_s,
        country_code: country_code.to_s,
        visitor_token: visitor_token,
        now: now
      )
      add_location_rollup_row!(
        deduped,
        site_id: normalize_site_id(site),
        bucket_start: bucket,
        dimension: "cities",
        value: city_value.to_s,
        country_code: country_code.to_s,
        visitor_token: visitor_token,
        now: now
      )
    end

    deduped.values
  end

  private
    def event_by_event_id(event_id:, site:)
      return if event_id.blank?

      scope = Ahoy::Event.where(event_id: event_id)
      scope = Analytics::Scope.apply(scope, site:) if site.present?
      scope.take
    end

    def recent_event_visit_ids(site:, since:)
      Ahoy::Event
        .for_analytics_site(site)
        .where("time >= ?", since)
        .distinct
        .pluck(:visit_id)
    end

    def apply_event_order(scope, order)
      case order.to_sym
      when :desc
        scope.order(time: :desc, id: :desc)
      else
        scope.order(:time, :id)
      end
    end

    def apply_visit_order(scope, order)
      case order
      when Hash
        scope.order(order)
      when :asc
        scope.order(:started_at, :id)
      else
        scope.order(started_at: :desc, id: :desc)
      end
    end

    def goal_event_scope(site:, range:, visit_ids:, goal_name:, goal:)
      if goal.blank? && goal_name.to_s.blank?
        Ahoy::Event.none
      else
        scope = Ahoy::Event
          .for_analytics_site(site)
          .joins(:visit)
          .where(time: range)
          .where(visit_id: visit_ids)

        if goal.present?
          Analytics::Goals.apply(scope, goal)
        else
          scope.where(name: goal_name.to_s)
        end
      end
    end

    def property_scope(site:, range:, visit_ids:, names:, exclude_names:, goal:)
      scope = Ahoy::Event
        .for_analytics_site(site)
        .joins(:visit)
        .where.not(properties: [ nil, {} ])
      scope = scope.where(time: range) if range.present?
      scope = scope.where(visit_id: visit_ids) if visit_ids.present?

      if goal.present?
        Analytics::Goals.apply(scope, goal)
      else
        scope = scope.where(name: names) if names.present?
        scope = scope.where.not(name: exclude_names) if exclude_names.present?
        scope
      end
    end

    def apply_property_filters(scope, property_filters)
      Array(property_filters).reduce(scope) do |filtered_scope, entry|
        if entry.is_a?(Array) && entry.length == 3
          operator, key, value = entry
        else
          key, value = entry
          operator = "is"
        end

        next filtered_scope unless Analytics::Properties.filter_key?(key)

        property_name = Analytics::Properties.filter_name(key)
        next filtered_scope if property_name.blank? || value.to_s.strip.empty?

        value_expr = Analytics::Properties.event_property_value(property_name)
        scoped = filtered_scope.where(Analytics::Properties.event_property_exists(property_name))

        case operator.to_s
        when "contains"
          scoped.where(Analytics::Properties.event_property_value_lower(property_name).matches(Analytics::Search.contains_pattern(value)))
        when "is_not", "not_eq"
          scoped.where(value_expr.not_eq(value.to_s))
        else
          scoped.where(value_expr.eq(value.to_s))
        end
      end
    end

    def normalize_site_id(site)
      case site
      when Analytics::Site
        site.id
      else
        site.presence
      end
    end

    def normalize_bucket_start(value)
      return if value.blank?

      (value.respond_to?(:in_time_zone) ? value.in_time_zone : Time.zone.parse(value.to_s))&.beginning_of_hour
    rescue ArgumentError, TypeError
      nil
    end

    def slice_model_data(model, data)
      column_names = model.try(:column_names) || model.attribute_names
      data.slice(*column_names.map(&:to_sym)).select { |_, value| !value.nil? }
    end

    def unique_exception?(error)
      return true if defined?(ActiveRecord::RecordNotUnique) && error.is_a?(ActiveRecord::RecordNotUnique)
      return true if defined?(PG::UniqueViolation) && error.is_a?(PG::UniqueViolation)

      false
    end

    def page_rollup_expression
      "COALESCE(NULLIF(split_part(ahoy_events.properties->>'page', CHR(63), 1), ''), '(unknown)')"
    end

    def add_location_rollup_row!(deduped, site_id:, bucket_start:, dimension:, value:, country_code:, visitor_token:, now:)
      key = [ dimension, value, country_code, visitor_token ]
      deduped[key] ||= {
        analytics_site_id: site_id,
        bucket_start: bucket_start,
        dimension: dimension,
        value: value,
        country_code: country_code,
        visitor_token: visitor_token,
        created_at: now,
        updated_at: now
      }
    end
end
