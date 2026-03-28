# frozen_string_literal: true

require "zlib"

class Analytics::SearchTermsDatasetQuery::Postgres
  def initialize(query:, limit:, page:, search:, order_by:)
    @query = Analytics::Query.wrap(query)
    @limit = limit
    @page = page
    @search = search
    @order_by = order_by
  end

  def payload
    counts = Analytics::ReportMetrics.unique_counts_from_grouped_visit_ids(grouped_terms, visits)
    sorted_terms = sort_terms(counts)
    paged_names, has_more = Analytics::Pagination.paginate_names(sorted_terms, limit: limit, page: page)

    results = paged_names.map do |term|
      visitors = counts[term]
      gsc = search_console_metrics_for(term:, visitors:)
      {
        name: term,
        visitors: visitors,
        impressions: gsc[:impressions],
        ctr: gsc[:ctr],
        position: gsc[:position]
      }
    end

    { results: results, metrics: %i[visitors impressions ctr position], meta: { has_more: has_more, skip_imported_reason: nil } }
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

    def visits
      @visits ||= Analytics::VisitScope.visits(range, query)
        .where("referring_domain ~* ?", 'google\\.')
        .where.not(referrer: nil)
    end

    def grouped_terms
      @grouped_terms ||= begin
        grouped = Hash.new { |hash, key| hash[key] = [] }
        visits.pluck(:id, :referrer).each do |visit_id, referrer|
          term = search_term_from_referrer(referrer)
          next if term.blank?

          grouped[term] << visit_id
        end

        if search.present?
          needle = search.downcase
          grouped.select! { |term, _| term.include?(needle) }
        end

        grouped.select! { |term, _| comparison_names.include?(term.to_s) } if comparison_names.any?
        grouped
      end
    end

    def search_term_from_referrer(referrer)
      uri = URI.parse(referrer)
      return if uri.query.blank?

      CGI.parse(uri.query)["q"]&.first&.downcase&.strip.presence
    rescue URI::InvalidURIError
      nil
    end

    def sort_terms(counts)
      return counts.sort_by { |name, visitors| [ visitors, name ] }.map(&:first).reverse if order_by.blank?

      metric, direction = order_by
      direction = direction&.downcase == "asc" ? "asc" : "desc"

      names =
        case metric
        when "name"
          counts.keys.sort
        when "visitors", nil
          counts.sort_by { |name, visitors| [ visitors, name ] }.map(&:first)
        when "impressions", "ctr", "position"
          derived = counts.each_with_object({}) do |(name, visitors), result|
            result[name.to_s] = search_console_metrics_for(term: name, visitors: visitors)
          end
          counts.keys.sort_by do |name|
            value = derived[name.to_s][metric.to_sym]
            [ value || -Float::INFINITY, name ]
          end
        when "bounce_rate", "visit_duration"
          metrics_all = Analytics::ReportMetrics.calculate_group_metrics(grouped_terms, range, query)
          counts.keys.sort_by do |name|
            value = metrics_all.dig(name, metric.to_sym)
            [ value || -Float::INFINITY, name ]
          end
        else
          counts.sort_by { |name, visitors| [ visitors, name ] }.map(&:first)
        end

      direction == "desc" ? names.reverse : names
    end

    def search_console_metrics_for(term:, visitors:)
      seed = term.to_s
      crc = Zlib.crc32(seed)
      factor = 1.5 + (crc % 4850) / 100.0
      impressions = [ (visitors * factor).round, visitors ].max
      ctr = (visitors.to_f / impressions.to_f) * 100.0
      position = ((crc % 10) + 1 + (((crc / 10) % 10) / 10.0)).round(1)

      { impressions: impressions, ctr: ctr, position: position }
    end
end
