# frozen_string_literal: true

module Admin
  module Analytics
    class ProfilesController < BaseController
      def index
        limit, page = parsed_pagination
        render json: camelize_keys(
          AnalyticsProfile.profiles_payload(
            @query,
            limit: limit,
            page: page,
            search: normalized_search
          )
        )
      end

      def show
        render json: camelize_keys(
          AnalyticsProfile.journey_payload(params[:id], @query)
        )
      end
    end
  end
end
