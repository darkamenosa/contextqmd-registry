# frozen_string_literal: true

class Analytics::VisitAttributes
  def self.normalize(data, request: nil)
    new(data, request:).normalize
  end

  def initialize(data, request:)
    @attrs = data.with_indifferent_access.dup
    @request = request
  end

  def normalize
    if request.present?
      attrs[:visitor_token] = Analytics::AnonymousIdentity.current(request) || attrs[:visitor_token]
      attrs[:browser_id] ||= Analytics::BrowserIdentity.current(request)
      attrs[:hostname] ||= request.host
      enrich_technology!
      normalize_landing_page!
      normalize_referrer!
      normalize_screen_size!
      enrich_location!
      canonicalize_country!(fallback_code: ClientIp.country_hint(request))
    else
      attrs[:hostname] ||= host_from_url(attrs[:landing_page])
      normalize_screen_size!
      canonicalize_country!
    end

    attrs
  end

  private
    attr_reader :attrs, :request

    def enrich_technology!
      detector = DeviceDetector.new(request.user_agent.to_s)
      attrs[:browser] ||= detector.name.presence
      attrs[:browser_version] ||= detector.full_version.presence
      attrs[:os] ||= detector.os_name.presence
      attrs[:os_version] ||= detector.os_full_version.presence
      attrs[:device_type] ||= normalized_device_type(detector)
    rescue StandardError
      attrs
    end

    def normalize_landing_page!
      landing_page = attrs[:landing_page].to_s
      return unless landing_page.blank? || Analytics::InternalPaths.report_internal_path?(normalized_path(landing_page))
      return if request.referer.blank?

      attrs[:landing_page] = request.referer
    end

    def normalize_referrer!
      referrer = request.referer
      return if referrer.blank?

      ref_host = host_from_url(referrer)
      site_host = attrs[:hostname].presence || request.host
      return unless ref_host.present?

      if internal_referrer?(ref_host, site_host)
        attrs[:referrer] = nil if attrs[:referrer].to_s == referrer
        attrs[:referring_domain] = nil
      else
        attrs[:referring_domain] ||= ref_host
      end
    end

    def normalize_screen_size!
      normalized_size = Analytics::Devices.categorize_screen_size(attrs[:screen_size])
      return if normalized_size.blank? || normalized_size == "(not set)"

      attrs[:screen_size] = normalized_size
    end

    def enrich_location!
      return unless defined?(MaxmindGeo) && MaxmindGeo.available?

      record = lookup_maxmind_record
      return unless record

      canonicalize_country!(fallback_code: record[:country_iso])
      attrs[:region] ||= record[:subdivisions]&.first
      attrs[:city] ||= record[:city]
      attrs[:latitude] ||= record[:latitude]
      attrs[:longitude] ||= record[:longitude]
    end

    def canonicalize_country!(fallback_code: nil)
      resolved = Analytics::Country.resolve(
        country: attrs[:country],
        country_code: attrs[:country_code] || fallback_code
      )
      attrs[:country_code] = resolved.code
      attrs[:country] = resolved.name
    end

    def lookup_maxmind_record
      client_ip = ClientIp.public(request, fallback_ip: attrs[:ip])
      client_ip ? MaxmindGeo.lookup(client_ip) : nil
    end

    def normalized_device_type(detector)
      case detector.device_type
      when "smartphone" then "Mobile"
      when "tv" then "TV"
      else detector.device_type.to_s.presence&.titleize
      end
    end

    def internal_referrer?(ref_host, site_host)
      local_host?(ref_host) || same_site_host?(ref_host, site_host)
    end

    def same_site_host?(ref_host, site_host)
      return false if ref_host.to_s.strip.empty? || site_host.to_s.strip.empty?

      ref_host.to_s.downcase.sub(/^www\./, "") == site_host.to_s.downcase.sub(/^www\./, "")
    end

    def local_host?(host)
      normalized_host = host.to_s.downcase
      return true if normalized_host == "localhost"

      ip = IPAddr.new(normalized_host) rescue nil
      ip && (ip.loopback? || ip.to_s == "0.0.0.0" || ip.to_s == "::1")
    rescue StandardError
      false
    end

    def host_from_url(value)
      return nil if value.blank?

      URI.parse(value.to_s).host
    rescue URI::InvalidURIError
      nil
    end

    def normalized_path(value)
      URI.parse(value).path
    rescue URI::InvalidURIError
      value.to_s
    end
end
