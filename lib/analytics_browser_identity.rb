# frozen_string_literal: true

module AnalyticsBrowserIdentity
  extend self

  COOKIE_NAME = "cq_analytics_browser_id"
  REQUEST_ENV_KEY = "analytics.browser_id"
  COOKIE_DURATION = 2.years

  def current(request)
    return if request.nil?

    request.get_header(REQUEST_ENV_KEY).presence || cookie_value(request)
  end

  def ensure!(request, cookies:)
    existing = current(request)
    return existing if existing.present?

    browser_id = SecureRandom.uuid
    request.set_header(REQUEST_ENV_KEY, browser_id)
    cookies[COOKIE_NAME] = cookie_options(browser_id)
    browser_id
  end

  private
    def cookie_value(request)
      value = request.cookies[COOKIE_NAME].to_s.presence
      request.set_header(REQUEST_ENV_KEY, value) if value.present?
      value
    end

    def cookie_options(value)
      {
        value: value,
        expires: COOKIE_DURATION.from_now,
        httponly: true,
        same_site: :lax,
        secure: Rails.env.production?
      }
    end
end
