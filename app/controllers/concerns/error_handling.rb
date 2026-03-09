# frozen_string_literal: true

module ErrorHandling
  extend ActiveSupport::Concern

  included do
    rescue_from StandardError, with: :handle_internal_error
    rescue_from ActionController::RoutingError, ActiveRecord::RecordNotFound, with: :handle_not_found
    rescue_from ActionController::InvalidAuthenticityToken, with: :handle_session_expired
    rescue_from ActionController::UnknownFormat, with: :handle_unknown_format
  end

  private

    def handle_internal_error(exception)
      raise exception unless Rails.env.production?

      Rails.logger.error(exception.full_message)
      render_error_response(500, "Server Error", "Something went wrong on our end. We're working on it.")
    end

    def handle_not_found(_exception = nil)
      render_error_response(404, "Page Not Found", "The page you're looking for doesn't exist or has been moved.")
    end

    def handle_session_expired(_exception = nil)
      render_error_response(419, "Session Expired", "Your session has expired. Please refresh the page and try again.")
    end

    def handle_unknown_format(_exception = nil)
      render_error_response(406, "Not Acceptable", "The requested format is not supported.")
    end

    def render_error_response(status, title, message)
      if api_request?
        render_api_error(status, message)
      elsif request.format.html?
        render inertia: error_component, props: { status:, title:, message: }, status:
      else
        head status
      end
    end

    def render_api_error(status, message)
      render json: { error: message, status: Rack::Utils.status_code(status) }, status:
    end

    def error_component
      if request.path.start_with?("/admin")
        "admin/errors/show"
      elsif request.path.start_with?("/app")
        "app/errors/show"
      else
        "errors/show"
      end
    end

    def api_request?
      request.format.json? || request.authorization.to_s.start_with?("Bearer")
    end
end
