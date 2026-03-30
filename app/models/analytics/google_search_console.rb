# frozen_string_literal: true

module Analytics
  module GoogleSearchConsole
    class << self
      def unsupported_search_terms_filters?(query)
        unsupported_filters?(
          query,
          allowed_dimensions: %w[source page country],
          disallowed_dimensions: %w[
            channel
            referrer
            utm_source
            utm_medium
            utm_campaign
            utm_content
            utm_term
            entry_page
            exit_page
            region
            city
            browser
            browser_version
            os
            os_version
            size
            goal
          ]
        )
      end

      def unsupported_pages_filters?(query)
        unsupported_filters?(
          query,
          allowed_dimensions: %w[source page country goal],
          disallowed_dimensions: %w[
            channel
            referrer
            utm_source
            utm_medium
            utm_campaign
            utm_content
            utm_term
            entry_page
            exit_page
            region
            city
            browser
            browser_version
            os
            os_version
            size
          ]
        )
      end

      private
        def unsupported_filters?(query, allowed_dimensions:, disallowed_dimensions:)
          query = Analytics::Query.wrap(query)
          source_filter = query.filter_value(:source)

          if source_filter.present? && !Analytics::Sources.match_values("Google").include?(source_filter.to_s)
            return true
          end

          return true if query.filter_dimensions.any? do |dimension|
            disallowed_dimensions.include?(dimension) || Analytics::Properties.filter_key?(dimension)
          end

          query.filter_clauses.any? do |operator, dimension, _value|
            next false if operator.in?([ :comparison_name, :comparison_code ])
            next false if operator == :eq && dimension.to_s.in?(allowed_dimensions)

            true
          end
        end
    end
  end
end
