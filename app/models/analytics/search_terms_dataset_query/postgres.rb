# frozen_string_literal: true

class Analytics::SearchTermsDatasetQuery::Postgres
  FETCH_LIMIT = 500
  METRICS = %i[visitors impressions ctr position].freeze

  def initialize(query:, limit:, page:, search:, order_by:)
    @query = Analytics::Query.wrap(query)
    @limit = limit
    @page = page
    @search = search
    @order_by = order_by
  end

  def payload
    sorted_rows = sort_rows(filtered_rows)
    paged_rows = sorted_rows.slice(offset, limit) || []
    has_more = sorted_rows.length > (offset + paged_rows.length)

    {
      results: paged_rows.map do |row|
        {
          name: row.fetch(:name),
          visitors: row.fetch(:visitors),
          impressions: row.fetch(:impressions),
          ctr: row.fetch(:ctr),
          position: row.fetch(:position)
        }
      end,
      metrics: METRICS,
      meta: {
        has_more: has_more,
        skip_imported_reason: nil,
        metric_labels: {
          visitors: "Visitors",
          ctr: "CTR"
        }
      }
    }
  end

  private
    attr_reader :query, :limit, :page, :search, :order_by

    def range
      @range ||= begin
        raw_range, = Analytics::Ranges.range_and_interval_for(query.time_range_key, nil, query)
        raw_range
      end
    end

    def comparison_names
      query.comparison_filter_names
    end

    def offset
      [ page - 1, 0 ].max * limit
    end

    def filtered_rows
      rows = raw_rows
      if search.present?
        needle = search.to_s.downcase
        rows = rows.select { |row| row.fetch(:name).downcase.include?(needle) }
      end

      if comparison_names.any?
        allowed = comparison_names.to_set
        rows = rows.select { |row| allowed.include?(row.fetch(:name)) }
      end

      rows
    end

    def raw_rows
      @raw_rows ||= begin
        return [] if ::Analytics::Current.site.blank?

        aggregated_rows.map do |row|
          impressions = row.impressions.to_i
          {
            name: row.name.to_s,
            visitors: row.clicks.to_i,
            impressions: impressions,
            ctr: impressions.positive? ? ((row.clicks.to_f / impressions) * 100.0).round(1) : 0.0,
            position: impressions.positive? ? (row.position_impressions_sum.to_f / impressions).round(1) : 0.0
          }
        end
      end
    end

    def sort_rows(rows)
      metric, direction = normalized_order_by

      sorted = rows.sort_by do |row|
        value =
          case metric
          when "name"
            row.fetch(:name).downcase
          when "impressions"
            row.fetch(:impressions)
          when "ctr"
            row.fetch(:ctr)
          when "position"
            row.fetch(:position)
          else
            row.fetch(:visitors)
          end

        [ value, row.fetch(:name).downcase ]
      end

      direction == "desc" ? sorted.reverse : sorted
    end

    def normalized_order_by
      metric, direction = Array(order_by)
      normalized_metric = metric.to_s.presence || "visitors"
      normalized_direction = direction.to_s == "asc" ? "asc" : "desc"
      [ normalized_metric, normalized_direction ]
    end

    def aggregated_rows
      relation = Analytics::GoogleSearchConsole::QueryRow
        .for_site(::Analytics::Current.site)
        .for_search_type(Analytics::GoogleSearchConsole::Syncer::DEFAULT_SEARCH_TYPE)
        .within_dates(range.begin.to_date, range.end.to_date)

      if (page_value = query.filter_value(:page)).present?
        relation = relation.where(page: normalized_page_filter(page_value))
      end

      if (country_value = normalized_country_filter(query.filter_value(:country))).present?
        relation = relation.where(country: country_value)
      end

      if search.present?
        relation = relation.where("query ILIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(search.to_s)}%")
      end

      if comparison_names.any?
        relation = relation.where(query: comparison_names)
      end

      relation
        .group(:query)
        .select(
          "query AS name",
          "SUM(clicks) AS clicks",
          "SUM(impressions) AS impressions",
          "SUM(position_impressions_sum) AS position_impressions_sum"
        )
    end

    def normalized_page_filter(page_value)
      value = page_value.to_s.strip
      return if value.blank?

      Analytics::GoogleSearchConsole::QueryRow.normalize_page_value(value)
    end

    def normalized_country_filter(country_value)
      return if country_value.blank?

      alpha2 = Ahoy::Visit.normalize_country_code(country_value)
      ISO3166::Country[alpha2]&.alpha3
    end
end
