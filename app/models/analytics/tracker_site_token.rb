# frozen_string_literal: true

class Analytics::TrackerSiteToken
  PURPOSE = "analytics-tracker-site-token".freeze
  VERSION = 1
  DEFAULT_EXPIRY = 1.day

  Resolution = Data.define(:site, :boundary, :claims)

  class << self
    def generate(
      site:,
      boundary: nil,
      host: nil,
      path: nil,
      environment: Rails.env,
      mode: "first_party",
      expires_in: DEFAULT_EXPIRY
    )
      return nil if site.blank?

      resolved_boundaries = normalize_boundaries(site:, boundary:, host:, path:)
      issued_at = Time.current.to_i
      expires_at = issued_at + expires_in.to_i
      claims = {
        "v" => VERSION,
        "site_public_id" => site.public_id,
        "allowed_boundaries" => resolved_boundaries.map { |entry| boundary_claim(entry) },
        "allowed_hosts" => resolved_boundaries.map(&:host).compact_blank.uniq,
        "allowed_path_prefixes" => resolved_boundaries.map(&:path_prefix).compact_blank.uniq,
        "environment" => environment.to_s,
        "issued_at" => issued_at,
        "expires_at" => expires_at,
        "mode" => mode.to_s
      }

      verifier.generate(claims, purpose: PURPOSE, expires_in: expires_in)
    end

    def verify(token, host:, path:, environment: Rails.env)
      return nil if token.blank?

      claims = verifier.verified(token, purpose: PURPOSE)
      return nil unless valid_claims?(claims)

      normalized_host = Analytics::SiteBoundary.normalize_host(host)
      normalized_path = Analytics::SiteBoundary.normalize_path_prefix(path)

      return nil unless boundary_allowed?(claims.fetch("allowed_boundaries"), normalized_host, normalized_path)
      return nil unless claims.fetch("environment") == environment.to_s

      site = Analytics::Site.active.find_by(public_id: claims.fetch("site_public_id"))
      return nil if site.blank?

      boundary = Analytics::SiteBoundary.resolve(host: normalized_host, path: normalized_path)
      boundary = nil if boundary.present? && boundary.site != site

      Resolution.new(site:, boundary:, claims:)
    end

    private
      def verifier
        Rails.application.message_verifier(PURPOSE)
      end

      def valid_claims?(claims)
        claims.is_a?(Hash) &&
          claims["v"] == VERSION &&
          claims["site_public_id"].is_a?(String) &&
          claims["allowed_boundaries"].is_a?(Array) &&
          claims["allowed_hosts"].is_a?(Array) &&
          claims["allowed_path_prefixes"].is_a?(Array) &&
          claims["environment"].is_a?(String) &&
          claims["issued_at"].is_a?(Integer) &&
          claims["expires_at"].is_a?(Integer)
      end

      def resolve_boundary(site:, host:, path:)
        normalized_host = Analytics::SiteBoundary.normalize_host(host)
        normalized_path = Analytics::SiteBoundary.normalize_path_prefix(path)

        boundary = Analytics::SiteBoundary.resolve(host: normalized_host, path: normalized_path)
        return boundary if boundary&.site == site

        site.boundaries.find_by(primary: true)
      end

      def normalize_boundaries(site:, boundary:, host:, path:)
        boundaries = site.boundaries.order(primary: :desc, priority: :desc, id: :asc).to_a
        boundaries = [ boundary ] if boundary.present?
        if boundaries.empty?
          fallback_boundary = resolve_boundary(site:, host:, path:)
          boundaries = [ fallback_boundary ].compact
        end

        if boundaries.empty?
          boundaries = [
            Analytics::SiteBoundary.new(
              site: site,
              host: Analytics::SiteBoundary.normalize_host(host) || site.canonical_hostname,
              path_prefix: Analytics::SiteBoundary.normalize_path_prefix(path)
            )
          ]
        end

        boundaries
          .compact
          .uniq { |entry| [ entry.host, entry.path_prefix ] }
      end

      def boundary_claim(boundary)
        {
          "host" => Analytics::SiteBoundary.normalize_host(boundary.host),
          "path_prefix" => Analytics::SiteBoundary.normalize_path_prefix(boundary.path_prefix)
        }
      end

      def boundary_allowed?(allowed_boundaries, normalized_host, normalized_path)
        return false if normalized_host.blank? || normalized_path.blank?

        allowed_boundaries.any? do |entry|
          next false unless entry.is_a?(Hash)

          allowed_host = Analytics::SiteBoundary.normalize_host(entry["host"])
          allowed_prefix = Analytics::SiteBoundary.normalize_path_prefix(entry["path_prefix"])

          allowed_host == normalized_host &&
            (allowed_prefix == "/" ||
              normalized_path == allowed_prefix ||
              normalized_path.start_with?("#{allowed_prefix}/"))
        end
      end
  end
end
