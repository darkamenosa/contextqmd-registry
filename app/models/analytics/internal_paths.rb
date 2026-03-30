# frozen_string_literal: true

module Analytics::InternalPaths
  TRANSPORT_PREFIXES = [
    "/analytics",
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

      REPORT_INTERNAL_PREFIXES.any? { |prefix| normalized.start_with?(prefix) }
    end

    def report_internal_sql_similar_pattern
      @report_internal_sql_similar_pattern ||= begin
        patterns = REPORT_INTERNAL_PREFIXES.map do |prefix|
          escaped = prefix.gsub("/", "\\/")
          if escaped.end_with?("\\/")
            "#{escaped}%"
          else
            "#{escaped}%"
          end
        end
        "(#{patterns.join('|')})"
      end
    end

    private
      def normalize_path(path)
        value = path.to_s.strip
        value.present? ? value : nil
      end
  end
end
