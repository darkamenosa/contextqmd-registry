# frozen_string_literal: true

require Rails.root.join("lib/analytics_browser_identity")

module AnalyticsBrowserTracking
  extend ActiveSupport::Concern

  included do
    before_action :ensure_analytics_browser_identity
  end

  private
    def ensure_analytics_browser_identity
      return unless request.get? || request.head?
      return unless request.format.html?

      AnalyticsBrowserIdentity.ensure!(request, cookies:)
    end
end
