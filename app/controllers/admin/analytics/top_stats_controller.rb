# frozen_string_literal: true

module Admin
  module Analytics
    class TopStatsController < BaseController
      def show
        cached = cache_for(:top_stats) { top_stats_payload(@query) }
        refresh_live_visitors_top_stat!(cached)
        render json: camelize_keys(cached)
      end
    end
  end
end
