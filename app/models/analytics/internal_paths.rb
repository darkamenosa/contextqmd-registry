# frozen_string_literal: true

module Analytics::InternalPaths
  TRANSPORT_PREFIXES = [
    "/analytics",
    "/a",
    "/ahoy"
  ].freeze

  TRACKER_ONLY_PREFIXES = [
    "/admin",
    "/.well-known"
  ].freeze

  SERVER_ONLY_PREFIXES = [
    "/api",
    "/rails/",
    "/assets/",
    "/up",
    "/jobs",
    "/webhooks"
  ].freeze

  REPORT_ONLY_PREFIXES = [
    "/cable",
    "/rails/",
    "/assets/",
    "/up",
    "/jobs",
    "/webhooks"
  ].freeze

  TRACKER_EXCLUDE_PREFIXES = (TRACKER_ONLY_PREFIXES + TRANSPORT_PREFIXES + [ "/cable" ]).freeze
  SERVER_EXCLUDED_PREFIXES = (TRACKER_ONLY_PREFIXES + SERVER_ONLY_PREFIXES + TRANSPORT_PREFIXES).freeze
  REPORT_INTERNAL_PREFIXES = (REPORT_ONLY_PREFIXES + TRANSPORT_PREFIXES).freeze

  class << self
    def tracker_exclude_prefixes
      TRACKER_EXCLUDE_PREFIXES
    end

    def server_excluded_prefixes
      SERVER_EXCLUDED_PREFIXES
    end

    def report_internal_prefixes
      REPORT_INTERNAL_PREFIXES
    end

    def report_internal_path?(path)
      normalized = normalize_path(path)
      return false if normalized.blank?

      REPORT_INTERNAL_PREFIXES.any? { |prefix| segment_prefix_match?(normalized, prefix) }
    end

    def report_internal_sql_similar_pattern
      @report_internal_sql_similar_pattern ||= begin
        patterns = REPORT_INTERNAL_PREFIXES.flat_map do |prefix|
          escaped = prefix.gsub("/", "\\/")
          if prefix.end_with?("/")
            "#{escaped}%"
          else
            [ escaped, "#{escaped}\\/%" ]
          end
        end
        "(#{patterns.join('|')})"
      end
    end

    def segment_prefix_match?(path, prefix)
      return false if path.blank? || prefix.blank?

      normalized_path = normalize_path(path)
      normalized_prefix = normalize_path(prefix)
      return false if normalized_path.blank? || normalized_prefix.blank?

      if normalized_prefix.end_with?("/")
        normalized_path.start_with?(normalized_prefix)
      else
        normalized_path == normalized_prefix || normalized_path.start_with?("#{normalized_prefix}/")
      end
    end

    private
      def normalize_path(path)
        value = path.to_s.strip
        value.present? ? value : nil
      end
  end
end
