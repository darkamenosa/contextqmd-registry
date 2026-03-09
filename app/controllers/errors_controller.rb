# frozen_string_literal: true

class ErrorsController < InertiaController
  # Error pages must render for guests and outside tenant scope.
  allow_unauthenticated_access
  disallow_account_scope

  def show
    payload = error_payload(params[:status].to_i)

    render_error_response(payload[:status], payload[:title], payload[:message])
  end

  private

    def error_payload(status)
      ERROR_PAGES.fetch(status, ERROR_PAGES[404])
    end

    ERROR_PAGES = {
      401 => { status: 401, title: "Unauthorized", message: "Please sign in to continue." },
      403 => { status: 403, title: "Access Denied", message: "You don't have permission to access this page." },
      404 => { status: 404, title: "Page Not Found", message: "The page you're looking for doesn't exist or has been moved." },
      406 => { status: 406, title: "Not Acceptable", message: "The requested format is not supported." },
      419 => { status: 419, title: "Session Expired", message: "Your session has expired. Please refresh the page and try again." },
      422 => { status: 422, title: "Unprocessable Request", message: "We couldn't process this request. Please try again." },
      500 => { status: 500, title: "Server Error", message: "Something went wrong on our end. We're working on it." },
      503 => { status: 503, title: "Under Maintenance", message: "We're performing scheduled maintenance. Please check back soon." }
    }.freeze
end
