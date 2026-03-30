# frozen_string_literal: true

class Analytics::TrackingSiteResolver
  Resolution = Data.define(:site, :boundary)

  class << self
    def resolve(host:, path: nil, url: nil)
      active_sites = ::Analytics::Site.active.order(:id).to_a
      return if active_sites.empty?

      return Resolution.new(site: active_sites.first, boundary: active_sites.first.boundaries.find_by(primary: true)) if active_sites.one?

      normalized_host = ::Analytics::SiteBoundary.normalize_host(host)
      return if normalized_host.blank?

      boundary = ::Analytics::SiteBoundary.resolve(host: normalized_host, path: path.presence || url)
      return if boundary.blank?

      Resolution.new(site: boundary.site, boundary:)
    end

    def resolve!(...)
      resolve(...) || raise(ActiveRecord::RecordNotFound, "Analytics site could not be resolved")
    end
  end
end
