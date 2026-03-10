# frozen_string_literal: true

module Api
  module V1
    class HealthController < BaseController
      skip_before_action :authenticate_api_token!

      def show
        render_data({ status: "ok", version: "1.0.0" })
      end
    end
  end
end
