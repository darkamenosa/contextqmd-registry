# frozen_string_literal: true

class Analytics::TrackerCorsHeaders
  ALLOW_METHODS = "POST, OPTIONS".freeze
  ALLOW_HEADERS = "Content-Type, X-CSRF-Token".freeze
  MAX_AGE = "86400".freeze

  class << self
    def apply!(headers)
      headers["Access-Control-Allow-Origin"] = "*"
      headers["Access-Control-Allow-Methods"] = ALLOW_METHODS
      headers["Access-Control-Allow-Headers"] = ALLOW_HEADERS
      headers["Access-Control-Max-Age"] = MAX_AGE
      headers["Vary"] = merge_vary(headers["Vary"], "Origin")
    end

    private
      def merge_vary(current, value)
        [ current, value ].compact.flat_map { |entry| entry.split(",") }.map(&:strip).reject(&:blank?).uniq.join(", ")
      end
  end
end
