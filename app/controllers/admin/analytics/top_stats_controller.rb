# frozen_string_literal: true

module Admin
  module Analytics
    class TopStatsController < BaseController
      def show
        cached = cache_for(:top_stats) { top_stats_payload(@query) }
        if cached[:top_stats]&.first&.dig(:name) == "Live visitors"
          cached[:top_stats][0][:value] = ::Analytics::LiveState.current_visitors
        end
        render json: camelize_keys(cached)
      end
    end
  end
end
