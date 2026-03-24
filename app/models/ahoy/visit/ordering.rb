module Ahoy::Visit::Ordering
  extend ActiveSupport::Concern

  class_methods do
    ALLOWED_METRICS = %w[
      name visitors pageviews percentage bounce_rate visit_duration conversion_rate
      time_on_page scroll_depth impressions ctr position visits exit_rate exits
    ].freeze

    # Accept both camelCase and snake_case metric names from the UI
    def normalize_metric_key(metric)
      key = metric.to_s
      alias_map = {
        "bounceRate" => "bounce_rate",
        "visitDuration" => "visit_duration",
        "timeOnPage" => "time_on_page",
        "conversionRate" => "conversion_rate",
        "exitRate" => "exit_rate"
      }
      key = alias_map[key] || key
      key.gsub(/([A-Z])/, '_\\1').downcase
    end

    # Parse Plausible-style order_by parameter: [[metric, direction]]
    # Returns [metric, direction] with metric whitelisted and direction sanitized
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
      metric = normalize_metric_key(metric)
      metric = "visitors" unless ALLOWED_METRICS.include?(metric)
      dir = direction.to_s.downcase == "asc" ? "asc" : "desc"
      [ metric, dir ]
    end

    # Generic ordering for analytics payloads.
    #
    # counts:      Hash(name => Integer) as the primary numeric to sort by for
    #              simple metrics (visitors/visits/pageviews/exits)
    # metrics_map: Hash(name => { metric_sym => Numeric }) for derived metrics
    #              like percentage, bounce_rate, visit_duration, exit_rate
    # order_by:    [metric, direction] as returned by parsed_order_by
    #
    # Returns: ordered array of names
    def order_names(counts:, metrics_map: {}, order_by: nil)
      metric, direction = order_by || [ "visitors", "desc" ]
      metric = normalize_metric_key(metric)
      dir = direction.to_s.downcase == "asc" ? :asc : :desc

      names = counts.keys

      sorted = case metric
      when "name"
        names.sort_by { |n| n.to_s.downcase }
      when "visitors", "visits", "pageviews", "exits"
        names.sort_by { |n| [ counts[n].to_i, n.to_s.downcase ] }
      when "percentage", "bounce_rate", "visit_duration", "exit_rate"
        names.sort_by do |n|
          v = metrics_map.dig(n, metric.to_sym)
          [ (v.nil? ? -Float::INFINITY : v), n.to_s.downcase ]
        end
      else
        # Fallback to primary counts
        names.sort_by { |n| [ counts[n].to_i, n.to_s.downcase ] }
      end

      dir == :asc ? sorted : sorted.reverse
    end

    # Ordering for goal conversion payloads.
    #
    # conversions: Hash(name => Integer) conversion counts per group
    # cr:          Hash(name => Float) conversion rates per group
    # order_by:    [metric, direction] as returned by parsed_order_by
    #
    # Returns: ordered array of names
    def order_names_with_conversions(conversions:, cr:, order_by: nil)
      return conversions.sort_by { |(n, v)| [ v, n.to_s.downcase ] }.map(&:first).reverse unless order_by

      metric, direction = order_by
      metric = normalize_metric_key(metric)
      dir = direction.to_s.downcase == "asc" ? :asc : :desc

      sorted = case metric
      when "name"
        conversions.keys.sort_by { |n| n.to_s.downcase }
      when "visitors"
        conversions.sort_by { |(n, v)| [ v, n.to_s.downcase ] }.map(&:first)
      when "conversion_rate"
        conversions.keys.sort_by { |n| [ cr[n] || -Float::INFINITY, n.to_s.downcase ] }
      else
        conversions.sort_by { |(n, v)| [ v, n.to_s.downcase ] }.map(&:first)
      end

      dir == :asc ? sorted : sorted.reverse
    end
  end
end
