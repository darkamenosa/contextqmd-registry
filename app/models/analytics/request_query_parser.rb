# frozen_string_literal: true

require "cgi"

class Analytics::RequestQueryParser
  class << self
    def parse(query_string:, params:, allowed_periods:)
      new(query_string:, params:, allowed_periods:).parse
    end
  end

  def initialize(query_string:, params:, allowed_periods:)
    @query_string = query_string.to_s
    @params = normalize_params(params)
    @allowed_periods = Array(allowed_periods).map(&:to_s)
  end

  def parse
    labels = parse_labels
    filters, advanced_filters = parse_filters
    match_day_of_week = cast_boolean(value_for(:match_day_of_week))

    if (city = filters["city"]).present? && city.match?(/^\d+$/) && labels[city].present?
      filters["city"] = labels[city]
      labels["city"] = labels[city]
      labels.delete(city)
    end

    if (region_code = filters["region"]).present? &&
        region_code.match?(/^[A-Za-z]{2}-[A-Za-z0-9]{1,3}$/) &&
        labels["region"].present?
      filters["region"] = labels["region"]
    end

    period = normalize_period(value_for(:period))
    comparison = normalize_comparison(value_for(:comparison))
    with_imported = cast_boolean(value_for(:with_imported))

    {
      period: period,
      comparison: comparison,
      match_day_of_week: match_day_of_week,
      date: value_for(:date),
      from: value_for(:from),
      to: value_for(:to),
      compare_from: value_for(:compare_from),
      compare_to: value_for(:compare_to),
      metric: value_for(:metric),
      interval: value_for(:interval),
      mode: value_for(:mode),
      funnel: value_for(:funnel),
      property: value_for(:property),
      dialog: value_for(:dialog),
      with_imported: with_imported,
      filters: filters,
      labels: labels,
      advanced_filters: advanced_filters,
      time_range: {
        key: period,
        date: value_for(:date),
        from: value_for(:from),
        to: value_for(:to),
        compare_from: value_for(:compare_from),
        compare_to: value_for(:compare_to),
        comparison: comparison,
        match_day_of_week: match_day_of_week
      }.compact,
      filter_clauses: build_filter_clauses(filters, advanced_filters),
      options: {
        mode: value_for(:mode),
        funnel: value_for(:funnel),
        property: value_for(:property),
        metric: value_for(:metric),
        interval: value_for(:interval),
        dialog: value_for(:dialog),
        with_imported: with_imported
      }.compact
    }.compact
  end

  private
    attr_reader :query_string, :params, :allowed_periods

    def normalize_params(value)
      hash =
        if value.respond_to?(:to_unsafe_h)
          value.to_unsafe_h
        elsif value.respond_to?(:to_h)
          value.to_h
        else
          {}
        end

      hash.with_indifferent_access
    end

    def query_params
      @query_params ||= CGI.parse(query_string)
    end

    def value_for(key)
      params[key]
    end

    def parse_labels
      tokens = Array(query_params["l"]) | Array(value_for(:l)).compact

      tokens.each_with_object({}) do |token, labels|
        key, value = token.to_s.split(",", 2)
        next if key.blank? || value.blank?

        labels[key] = value
      end
    end

    def parse_filters
      tokens = Array(query_params["f"]) | Array(value_for(:f)).compact
      return [ {}, [] ] if tokens.empty?

      filters = {}
      advanced = []

      tokens.each do |token|
        parts = token.to_s.split(",", 3)
        next if parts.length < 3

        operator = parts[0].to_s
        dimension = parts[1].to_s
        clause = parts[2].to_s
        next if dimension.blank? || clause.blank?

        if operator == "is"
          if dimension == "event:goal" || dimension == "goal"
            filters["goal"] = clause
          else
            filters[dimension] = clause
          end
        elsif operator.in?([ "is_not", "contains" ])
          advanced << [ operator, dimension, clause ]
        end
      end

      [ filters, advanced ]
    end

    def normalize_period(value)
      period = value.to_s
      allowed_periods.include?(period) ? period : "day"
    end

    def normalize_comparison(value)
      comparison = value.to_s
      comparison == "off" ? nil : value
    end

    def cast_boolean(value)
      return nil if value.nil?

      ActiveModel::Type::Boolean.new.cast(value)
    end

    def build_filter_clauses(filters, advanced_filters)
      clauses = filters.to_h.map do |dimension, value|
        [ :eq, dimension.to_sym, value ]
      end

      clauses.concat(Array(advanced_filters).filter_map do |operator, dimension, value|
        next if dimension.blank?

        normalized_operator =
          case operator.to_s
          when "is_not" then :not_eq
          when "contains" then :contains
          else :eq
          end

        [ normalized_operator, dimension.to_sym, value ]
      end)

      clauses
    end
end
