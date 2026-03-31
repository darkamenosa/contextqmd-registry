# frozen_string_literal: true

class Analytics::TrackedSiteAttributes
  class << self
    def merge!(attrs, request: nil, fallback_visit: nil, environment: Rails.env)
      tracked_url = attrs[:landing_page].presence || fallback_visit&.landing_page
      resolution = Analytics::TrackedSiteScope.resolve(
        host: host_from(tracked_url:, attrs:, fallback_visit:, request:),
        url: tracked_url,
        path: attrs[:path],
        site_token: attrs[:site_token].presence,
        website_id: attrs[:website_id].presence,
        environment: environment
      )

      if resolution&.invalid_claim?
        raise Analytics::AhoyStore::InvalidTrackedSiteClaim
      end

      if resolution.present?
        attrs[:analytics_site_id] ||= resolution.site.id
        attrs[:analytics_site_boundary_id] ||= resolution.boundary&.id
      end

      attrs
    end

    private
      def host_from(tracked_url:, attrs:, fallback_visit:, request:)
        host_from_url(tracked_url) ||
          attrs[:hostname].presence ||
          fallback_visit&.hostname ||
          request&.host
      end

      def host_from_url(value)
        return nil if value.blank?

        URI.parse(value.to_s).host
      rescue URI::InvalidURIError
        nil
      end
  end
end
