# frozen_string_literal: true

class Analytics::TrackedSiteScope
  Resolution = Data.define(:site, :boundary, :invalid_claim) do
    def invalid_claim?
      invalid_claim == true
    end
  end

  class << self
    def resolve(host:, url: nil, path: nil, site_token: nil, website_id: nil, environment: Rails.env)
      normalized_path = path.presence || path_from_url(url)
      boundary_resolution = strict_boundary_resolution(host:, path: normalized_path, url:)

      if site_token.present?
        resolve_site_token(
          site_token: site_token,
          boundary_resolution: boundary_resolution,
          host: host,
          path: normalized_path,
          environment: environment
        )
      elsif website_id.present?
        resolve_website_id(
          website_id: website_id,
          boundary_resolution: boundary_resolution,
          host: host,
          path: normalized_path
        )
      else
        fallback_resolution = boundary_resolution.presence || ::Analytics::TrackingSiteResolver.resolve(host:, path: normalized_path, url:)
        return if fallback_resolution.blank?

        Resolution.new(site: fallback_resolution.site, boundary: fallback_resolution.boundary, invalid_claim: false)
      end
    end

    private
      def strict_boundary_resolution(host:, path:, url:)
        boundary = ::Analytics::SiteBoundary.resolve(host:, path: path.presence || url)
        return if boundary.blank?

        Resolution.new(site: boundary.site, boundary: boundary, invalid_claim: false)
      end

      def resolve_site_token(site_token:, boundary_resolution:, host:, path:, environment:)
        token_resolution = ::Analytics::TrackerSiteToken.verify(
          site_token,
          host: host,
          path: path,
          environment: environment
        )

        if token_resolution.blank?
          log_invalid_site_token(host:, path:)
          return invalid_resolution
        end

        if boundary_resolution.present? && boundary_resolution.site != token_resolution.site
          log_site_token_mismatch(
            token_site: token_resolution.site,
            boundary_site: boundary_resolution.site,
            host: host,
            path: path
          )
          return invalid_resolution
        end

        resolution = boundary_resolution.presence || token_resolution
        Resolution.new(site: resolution.site, boundary: resolution.boundary, invalid_claim: false)
      end

      def resolve_website_id(website_id:, boundary_resolution:, host:, path:)
        explicit_site = ::Analytics::Site.active.find_by(public_id: website_id.to_s)
        if explicit_site.blank?
          log_invalid_website_id(website_id:, host:, path:)
          return invalid_resolution
        end

        if boundary_resolution.blank?
          log_invalid_website_id(website_id:, host:, path:)
          return invalid_resolution
        end

        if boundary_resolution.site != explicit_site
          log_website_id_mismatch(
            website_id: website_id,
            website_site: explicit_site,
            boundary_site: boundary_resolution.site,
            host: host,
            path: path
          )
          return invalid_resolution
        end

        Resolution.new(site: explicit_site, boundary: boundary_resolution.boundary, invalid_claim: false)
      end

      def invalid_resolution
        Resolution.new(site: nil, boundary: nil, invalid_claim: true)
      end

      def path_from_url(url)
        return nil if url.blank?

        URI.parse(url.to_s).path
      rescue URI::InvalidURIError
        nil
      end

      def log_invalid_site_token(host:, path:)
        Rails.logger.warn("[analytics] rejected invalid site token for host=#{host.inspect} path=#{path.inspect}")
      end

      def log_site_token_mismatch(token_site:, boundary_site:, host:, path:)
        Rails.logger.warn(
          "[analytics] rejected mismatched site token token_site=#{token_site.public_id.inspect} boundary_site=#{boundary_site.public_id.inspect} host=#{host.inspect} path=#{path.inspect}"
        )
      end

      def log_invalid_website_id(website_id:, host:, path:)
        Rails.logger.warn(
          "[analytics] rejected website_id without matching site boundary website_id=#{website_id.inspect} host=#{host.inspect} path=#{path.inspect}"
        )
      end

      def log_website_id_mismatch(website_id:, website_site:, boundary_site:, host:, path:)
        Rails.logger.warn(
          "[analytics] rejected mismatched website_id website_id=#{website_id.inspect} website_site=#{website_site.public_id.inspect} boundary_site=#{boundary_site.public_id.inspect} host=#{host.inspect} path=#{path.inspect}"
        )
      end
  end
end
