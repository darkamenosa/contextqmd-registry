# frozen_string_literal: true

module Analytics
  class CorsController < ActionController::Base
    skip_forgery_protection

    def preflight
      Analytics::TrackerCorsHeaders.apply!(response.headers)
      head :no_content
    end
  end
end
