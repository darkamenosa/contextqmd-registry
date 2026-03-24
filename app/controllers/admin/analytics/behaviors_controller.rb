# frozen_string_literal: true

module Admin
  module Analytics
    class BehaviorsController < BaseController
      def index
        limit, page = parsed_pagination
        search = normalized_search
        payload = cache_for([ :behaviors, @query[:mode], @query[:funnel], limit, page, search, params[:order_by] ]) do
          behaviors_payload(@query, limit:, page:, search:)
        end
        render json: camelize_keys(payload)
      end
    end
  end
end
