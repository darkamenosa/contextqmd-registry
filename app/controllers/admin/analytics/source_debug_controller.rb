# frozen_string_literal: true

module Admin
  module Analytics
    class SourceDebugController < BaseController
      def show
        source = params[:source].to_s
        return render json: camelize_keys(empty_payload), status: :ok if source.blank?

        payload = cache_for([ :source_debug, source, @query[:filters], @query[:period] ]) do
          Ahoy::Visit.source_debug_payload(@query, source)
        end

        render json: camelize_keys(payload)
      end

      private
        def empty_payload
          {
            source: {
              requested_value: "",
              normalized_value: "",
              kind: "referral",
              favicon_domain: nil,
              visitors: 0,
              visits: 0,
              fallback_count: 0
            },
            channels: [],
            matched_rules: [],
            match_strategies: [],
            raw_referring_domains: [],
            raw_utm_sources: [],
            raw_referrers: [],
            latest_samples: []
          }
        end
    end
  end
end
