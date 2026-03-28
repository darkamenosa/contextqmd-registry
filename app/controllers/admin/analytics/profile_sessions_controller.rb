# frozen_string_literal: true

module Admin
  module Analytics
    class ProfileSessionsController < BaseController
      def index
        limit, page = parsed_pagination
        render json: camelize_keys(
          AnalyticsProfile.sessions_list_payload(
            params[:profile_id],
            limit: limit,
            page: page
          )
        )
      end

      def show
        render json: camelize_keys(
          AnalyticsProfile.session_payload(
            params[:profile_id],
            params[:id],
            @query
          )
        )
      end
    end
  end
end
