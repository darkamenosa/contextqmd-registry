# frozen_string_literal: true

class Analytics::AdminSiteResolver
  Resolution = Data.define(:site, :boundary)

  class << self
    def resolve(request: nil, explicit_site_id: nil)
      if explicit_site_id.present?
        if explicit_site_id.to_s == "current"
          active_sites = ::Analytics::Site.active.order(:id).to_a
          return if active_sites.empty?
          return Resolution.new(site: active_sites.first, boundary: active_sites.first.boundaries.find_by(primary: true)) if active_sites.one?
        end

        site = ::Analytics::Site.active.find_by!(public_id: explicit_site_id.to_s)
        return Resolution.new(site:, boundary: site.boundaries.find_by(primary: true))
      end

      active_sites = ::Analytics::Site.active.order(:id).to_a
      return if active_sites.empty?

      return Resolution.new(site: active_sites.first, boundary: active_sites.first.boundaries.find_by(primary: true)) if active_sites.one?

      host_resolution = resolve_for_host(request&.host)
      return host_resolution if host_resolution.present?

      nil
    end

    def resolve!(...)
      resolve(...) || raise(ActiveRecord::RecordNotFound, "Analytics site could not be resolved")
    end

    def selection_required?(explicit_site_id: nil, request: nil, host: nil)
      return false if explicit_site_id.present?

      return false if ::Analytics::Site.active.limit(2).count <= 1

      resolve_for_host(host || request&.host).nil?
    end

    private
      def resolve_for_host(host)
        normalized_host = ::Analytics::SiteBoundary.normalize_host(host)
        return if normalized_host.blank?

        boundaries = ::Analytics::SiteBoundary.joins(:site).merge(::Analytics::Site.active).where(host: normalized_host).to_a
        site = boundaries.map(&:site).uniq.one? ? boundaries.first.site : nil
        return if site.blank?

        boundary =
          boundaries.find(&:primary?) ||
          boundaries.max_by { |entry| [ entry.path_prefix.to_s.length, entry.priority.to_i ] } ||
          site.boundaries.find_by(primary: true)

        Resolution.new(site:, boundary:)
      end
  end
end
