# frozen_string_literal: true

module Admin
  module Analytics
    class ProfileSessionsController < BaseController
      def index
        limit, page = parsed_pagination
        date = parsed_session_date
        if params[:date].present? && date.nil?
          render json: { error: "Invalid date" }, status: :unprocessable_content
          return
        end

        render json: camelize_keys(
          AnalyticsProfile.sessions_list_payload(
            params[:profile_id],
            limit: limit,
            page: page,
            date: date
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

      private
        def parsed_session_date
          raw = params[:date].to_s.strip
          return nil if raw.blank?

          Date.iso8601(raw)
        rescue ArgumentError
          nil
        end
    end
  end
end
