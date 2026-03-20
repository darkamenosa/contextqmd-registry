# frozen_string_literal: true

class ApplicationController < ActionController::Base
  include Authentication
  include Authorization
  include ErrorHandling
  include CurrentRequest
  include CurrentTimezone
  include SetPlatform
  include RoutingHeaders
  include RequestForgeryProtection

  etag { "v1" }
  allow_browser versions: :modern

  before_action :redirect_trailing_slash

  private

    # Prevent duplicate content from trailing-slash URLs (preserves query params)
    def redirect_trailing_slash
      return if mounted_root_request?

      if request.get? && request.path.length > 1 && request.path.end_with?("/")
        path = request.path.chomp("/")
        path = "#{path}?#{request.query_string}" if request.query_string.present?
        redirect_to path, status: :moved_permanently
      end
    end

    def mounted_root_request?
      request.path_info == "/" && request.script_name.present?
    end
end
