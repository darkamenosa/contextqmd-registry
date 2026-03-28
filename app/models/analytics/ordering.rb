# frozen_string_literal: true

module Analytics::Ordering
  ALLOWED_METRICS = %w[
    name visitors pageviews percentage bounce_rate visit_duration conversion_rate
    time_on_page scroll_depth impressions ctr position visits exit_rate exits
  ].freeze

  class << self
    def normalize_metric(metric)
      key = metric.to_s
      alias_map = {
        "bounceRate" => "bounce_rate",
        "visitDuration" => "visit_duration",
        "timeOnPage" => "time_on_page",
        "conversionRate" => "conversion_rate",
        "exitRate" => "exit_rate"
      }
      key = alias_map[key] || key
      key.gsub(/([A-Z])/, '_\1').downcase
    end

    def parsed_order_by(param)
      return nil unless param.present?

      raw = case param
      when String
        begin
          JSON.parse(param)
        rescue JSON::ParserError
          nil
        end
      when Array
        param
      end
      return nil unless raw.is_a?(Array) && raw.first.is_a?(Array)

      metric, direction = raw.first
      metric = normalize_metric(metric)
      metric = "visitors" unless ALLOWED_METRICS.include?(metric)
      dir = direction.to_s.downcase == "asc" ? "asc" : "desc"
      [ metric, dir ]
    end

    def order_names(counts:, metrics_map: {}, order_by: nil)
      metric, direction = order_by || [ "visitors", "desc" ]
      metric = normalize_metric(metric)
      dir = direction.to_s.downcase == "asc" ? :asc : :desc

      names = counts.keys

      sorted = case metric
      when "name"
        names.sort_by { |name| name.to_s.downcase }
      when "visitors", "visits", "pageviews", "exits"
        names.sort_by { |name| [ counts[name].to_i, name.to_s.downcase ] }
      when "percentage", "bounce_rate", "visit_duration", "exit_rate"
        names.sort_by do |name|
          value = metrics_map.dig(name, metric.to_sym)
          [ (value.nil? ? -Float::INFINITY : value), name.to_s.downcase ]
        end
      else
        names.sort_by { |name| [ counts[name].to_i, name.to_s.downcase ] }
      end

      dir == :asc ? sorted : sorted.reverse
    end

    def order_names_with_conversions(conversions:, rates: nil, cr: nil, order_by: nil)
      rates ||= cr || {}

      return conversions.sort_by { |(name, value)| [ value, name.to_s.downcase ] }.map(&:first).reverse unless order_by

      metric, direction = order_by
      metric = normalize_metric(metric)
      dir = direction.to_s.downcase == "asc" ? :asc : :desc

      sorted = case metric
      when "name"
        conversions.keys.sort_by { |name| name.to_s.downcase }
      when "visitors"
        conversions.sort_by { |(name, value)| [ value, name.to_s.downcase ] }.map(&:first)
      when "conversion_rate"
        conversions.keys.sort_by { |name| [ rates[name] || -Float::INFINITY, name.to_s.downcase ] }
      else
        conversions.sort_by { |(name, value)| [ value, name.to_s.downcase ] }.map(&:first)
      end

      dir == :asc ? sorted : sorted.reverse
    end
  end
end
