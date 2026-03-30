# frozen_string_literal: true

require_relative "../client_ip"
require_relative "country"
require_relative "anonymous_identity"
require_relative "browser_identity"
require_relative "visit_boundary"

class Analytics::AhoyStore < Ahoy::DatabaseStore
  class InvalidTrackedSiteClaim < StandardError; end

  def visit_columns
    super + %i[hostname screen_size browser_version browser_id country_code analytics_site_id analytics_site_boundary_id]
  end

  def visit
    unless defined?(@visit)
      if ahoy.send(:existing_visit_token) || ahoy.instance_variable_get(:@visit_token)
        @visit = visit_model.where(visit_token: ahoy.visit_token).take if ahoy.visit_token
      elsif !Ahoy.cookies?
        @visit = if force_new_visit_boundary?
          nil
        else
          visit_model
            .where(visitor_token: anonymous_visitor_tokens)
            .where(started_at: Ahoy.visit_duration.ago..)
            .order(started_at: :desc)
            .first
        end
      else
        @visit = nil
      end
    end

    @visit
  end

  def track_visit(data)
    attrs = normalize_visit_attrs(data)

    visit = super(attrs)
    Analytics::VisitBoundary.consume_force_new_visit!(Current.request) if Current.request
    visit = repair_existing_visit_after_conflict!(visit, attrs)
    resolve_analytics_profile(visit, occurred_at: visit&.started_at)
    Analytics::LiveState.broadcast_later(site: Analytics::SiteLocator.from_record(visit))
    visit
  rescue InvalidTrackedSiteClaim
    nil
  end

  def track_event(data)
    data = data.with_indifferent_access

    return nil if data[:name].to_s == "engagement" && visit.nil?

    visit = visit_or_create(started_at: data[:time])
    unless visit
      Ahoy.log "Event excluded since visit not created: #{data[:visit_token]}"
      return nil
    end

    event = event_model.new(slice_data(event_model, data))
    event.visit = visit
    event.analytics_site_id ||= visit.analytics_site_id if event.respond_to?(:analytics_site_id)
    event.analytics_site_boundary_id ||= visit.analytics_site_boundary_id if event.respond_to?(:analytics_site_boundary_id)
    event.time = visit.started_at if event.time < visit.started_at

    begin
      event.save!
    rescue => e
      raise e unless unique_exception?(e)
      return nil
    end

    repair_visit_from_event!(visit, event, site_token: data[:site_token])
    sync_event_site_scope!(event, visit)
    resolve_analytics_profile(visit, occurred_at: event.time)
    Analytics::LiveState.broadcast_later(
      site: Analytics::SiteLocator.from_record(visit) || Analytics::SiteLocator.from_record(event)
    )
    event
  rescue InvalidTrackedSiteClaim
    nil
  end

  def authenticate(data)
    super

    resolved_visit = visit
    resolve_analytics_profile(resolved_visit, occurred_at: Time.current)
    Analytics::LiveState.broadcast_later(site: Analytics::SiteLocator.from_record(resolved_visit))
  end

  private
    def normalize_visit_attrs(data)
      attrs = data.with_indifferent_access.dup
      req = Current.request

      if req
        attrs[:visitor_token] = Analytics::AnonymousIdentity.current(req) || attrs[:visitor_token]
        attrs[:browser_id] ||= Analytics::BrowserIdentity.current(req)
        attrs[:hostname] ||= req.host
        enrich_visit_technology!(attrs, req)
        normalize_request_landing_page!(attrs, req)
        normalize_referrer!(attrs, req.referer, site_host: attrs[:hostname].presence || req.host)
        enrich_visit_location!(attrs, req, data)
        canonicalize_country!(attrs, fallback_code: ClientIp.country_hint(req))
      else
        attrs[:hostname] ||= host_from_url(attrs[:landing_page] || data[:landing_page])
        canonicalize_country!(attrs)
      end

      merge_resolved_site_scope!(attrs, req:)

      attrs
    rescue InvalidTrackedSiteClaim
      raise
    rescue StandardError
      attrs
    end

    def repair_existing_visit_after_conflict!(visit, attrs)
      return visit if visit.is_a?(::Ahoy::Visit)

      existing_visit = visit_for_token(attrs[:visit_token])
      return visit unless existing_visit

      updates = {}
      if existing_visit.respond_to?(:has_attribute?) && existing_visit.has_attribute?(:browser_id)
        updates[:browser_id] = attrs[:browser_id] if existing_visit.browser_id.blank? && attrs[:browser_id].present?
      end
      updates[:hostname] = attrs[:hostname] if existing_visit.hostname.blank? && attrs[:hostname].present?
      updates[:browser] = attrs[:browser] if existing_visit.browser.blank? && attrs[:browser].present?
      updates[:browser_version] = attrs[:browser_version] if existing_visit.browser_version.blank? && attrs[:browser_version].present?
      updates[:os] = attrs[:os] if existing_visit.os.blank? && attrs[:os].present?
      updates[:os_version] = attrs[:os_version] if existing_visit.os_version.blank? && attrs[:os_version].present?
      updates[:device_type] = attrs[:device_type] if existing_visit.device_type.blank? && attrs[:device_type].present?
      merge_resolved_site_scope!(updates, req: Current.request, fallback_visit: existing_visit) if site_scope_missing?(existing_visit)
      if normalized_internal_referrer?(existing_visit.referring_domain, updates[:hostname] || existing_visit.hostname)
        updates[:referrer] = nil if existing_visit.referrer.present?
        updates[:referring_domain] = nil if existing_visit.referring_domain.present?
      end

      persist_visit_repairs!(
        existing_visit,
        updates,
        refresh_source_dimensions: updates.key?(:hostname) || updates.key?(:referrer) || updates.key?(:referring_domain) || source_dimensions_missing?(existing_visit)
      )
      existing_visit
    rescue StandardError
      visit
    end

    def repair_visit_from_event!(visit, event, site_token: nil)
      props = event.properties.to_h.with_indifferent_access
      updates = {}
      enrich_visit_technology!(updates, Current.request) if Current.request && visit_technology_missing?(visit)

      if visit.screen_size.blank?
        screen_size = normalized_screen_size(props[:screen_size])
        updates[:screen_size] = screen_size if screen_size.present?
      end

      url = props[:url]
      if url.present?
        updates[:landing_page] = url if visit_needs_landing_page_fix?(visit) || site_token.present?
        if site_token.present? || visit.hostname.blank?
          resolved_host = host_from_url(url)
          updates[:hostname] = resolved_host if resolved_host.present?
        end
      end

      if updates.key?(:landing_page) || updates.key?(:hostname) || site_scope_missing?(visit) || site_token.present?
        updates[:site_token] = site_token if site_token.present?
        merge_resolved_site_scope!(updates, req: Current.request, fallback_visit: visit)
        updates.delete(:site_token)
      end

      persist_visit_repairs!(
        visit,
        updates,
        refresh_source_dimensions: updates.key?(:landing_page) || updates.key?(:hostname)
      )
    rescue StandardError
      nil
    end

    def persist_visit_repairs!(visit, updates, refresh_source_dimensions: false)
      return if updates.empty? && !refresh_source_dimensions

      visit.assign_attributes(updates)
      columns = updates.dup
      if refresh_source_dimensions
        visit.assign_source_dimensions
        columns.merge!(visit.source_dimension_attributes)
      end

      visit.update_columns(columns) if columns.present?
    end

    def normalize_request_landing_page!(attrs, req)
      landing_page = attrs[:landing_page].to_s
      return unless landing_page.blank? || internal_path?(landing_page)
      return if req.referer.blank?

      attrs[:landing_page] = req.referer
    end

    def enrich_visit_technology!(attrs, req)
      return if req.nil?

      detector = DeviceDetector.new(req.user_agent.to_s)
      attrs[:browser] ||= detector.name.presence
      attrs[:browser_version] ||= detector.full_version.presence
      attrs[:os] ||= detector.os_name.presence
      attrs[:os_version] ||= detector.os_full_version.presence
      attrs[:device_type] ||= normalized_device_type(detector)
    rescue StandardError
      attrs
    end

    def normalize_referrer!(attrs, referrer, site_host:)
      return if referrer.blank?

      ref_host = host_from_url(referrer)
      return unless ref_host.present?

      if normalized_internal_referrer?(ref_host, site_host)
        attrs[:referrer] = nil if attrs[:referrer].to_s == referrer
        attrs[:referring_domain] = nil
      else
        attrs[:referring_domain] ||= ref_host
      end
    end

    def enrich_visit_location!(attrs, req, data)
      if defined?(MaxmindGeo) && MaxmindGeo.available?
        if (record = lookup_maxmind_record(req, data))
          canonicalize_country!(attrs, fallback_code: record[:country_iso])
          attrs[:region] ||= record[:subdivisions]&.first
          attrs[:city] ||= record[:city]
          attrs[:latitude] ||= record[:latitude]
          attrs[:longitude] ||= record[:longitude]
        end
      end
    end

    def canonicalize_country!(attrs, fallback_code: nil)
      resolved = Analytics::Country.resolve(
        country: attrs[:country],
        country_code: attrs[:country_code] || fallback_code
      )
      attrs[:country_code] = resolved.code
      attrs[:country] = resolved.name
    end

    def visit_for_token(token)
      return nil if token.blank?

      ::Ahoy::Visit.find_by(visit_token: token)
    end

    def visit_needs_landing_page_fix?(visit)
      landing_page = visit.landing_page.to_s
      landing_page.blank? || internal_path?(landing_page)
    end

    def visit_technology_missing?(visit)
      visit.browser.blank? ||
        visit.browser_version.blank? ||
        visit.os.blank? ||
        visit.os_version.blank? ||
        visit.device_type.blank?
    end

    def source_dimensions_missing?(visit)
      visit.source_label.blank? || visit.source_kind.blank? || visit.source_channel.blank?
    end

    def site_scope_missing?(visit)
      visit.respond_to?(:analytics_site_id) && visit.analytics_site_id.blank?
    end

    def normalized_device_type(detector)
      case detector.device_type
      when "smartphone" then "Mobile"
      when "tv" then "TV"
      else detector.device_type.to_s.presence&.titleize
      end
    end

    def normalized_internal_referrer?(ref_host, site_host)
      local_host?(ref_host) || same_site_host?(ref_host, site_host)
    end

    def host_from_url(value)
      return nil if value.blank?

      URI.parse(value.to_s).host
    rescue URI::InvalidURIError
      nil
    end

    def normalized_screen_size(raw_size)
      size = Analytics::Devices.categorize_screen_size(raw_size)
      return nil if size.blank? || size == "(not set)" || size == raw_size.to_s

      size
    end

    def internal_path?(value)
      return false if value.blank?
      path = begin
        URI.parse(value).path
      rescue URI::InvalidURIError
        value.to_s
      end.to_s
      Analytics::InternalPaths.report_internal_path?(path)
    end

    def same_site_host?(ref_host, site_host)
      return false if ref_host.to_s.strip.empty? || site_host.to_s.strip.empty?

      ref_host.to_s.downcase.sub(/^www\./, "") == site_host.to_s.downcase.sub(/^www\./, "")
    end

    def local_host?(host)
      h = host.to_s.downcase
      return true if h == "localhost"

      ip = IPAddr.new(h) rescue nil
      ip && (ip.loopback? || ip.to_s == "0.0.0.0" || ip.to_s == "::1")
    rescue StandardError
      false
    end

    def lookup_maxmind_record(req, data)
      client_ip = ClientIp.public(req, fallback_ip: data[:ip])
      client_ip ? MaxmindGeo.lookup(client_ip) : nil
    end

    def anonymous_visitor_tokens
      tokens = Analytics::AnonymousIdentity.tokens(request)
      tokens.presence || [ ahoy.visitor_token ].compact
    end

    def merge_resolved_site_scope!(attrs, req: nil, fallback_visit: nil)
      tracked_url = attrs[:landing_page].presence || fallback_visit&.landing_page
      resolved = resolved_site_scope(
        host: host_from_url(tracked_url) || attrs[:hostname].presence || fallback_visit&.hostname || req&.host,
        url: tracked_url,
        path: attrs[:path],
        site_token: attrs[:site_token].presence,
        website_id: attrs[:website_id].presence
      )
      raise InvalidTrackedSiteClaim if resolved&.invalid_claim?
      return attrs if resolved.blank?

      attrs[:analytics_site_id] ||= resolved.site.id
      attrs[:analytics_site_boundary_id] ||= resolved.boundary&.id
      attrs
    end

    def resolved_site_scope(host:, url: nil, path: nil, site_token: nil, website_id: nil)
      ::Analytics::TrackedSiteScope.resolve(
        host: host,
        url: url,
        path: path,
        site_token: site_token,
        website_id: website_id,
        environment: Rails.env
      )
    end

    def sync_event_site_scope!(event, visit)
      return unless event.respond_to?(:analytics_site_id)
      return if event.analytics_site_id.present? && event.analytics_site_boundary_id.present?

      updates = {}
      updates[:analytics_site_id] = visit.analytics_site_id if event.analytics_site_id.blank? && visit.analytics_site_id.present?
      if event.analytics_site_boundary_id.blank? && visit.analytics_site_boundary_id.present?
        updates[:analytics_site_boundary_id] = visit.analytics_site_boundary_id
      end
      return if updates.empty?

      event.update_columns(updates)
      event.assign_attributes(updates)
    rescue StandardError
      nil
    end

    def resolve_analytics_profile(visit, occurred_at:)
      return if visit.blank?

      visit.resolve_profile_later(
        browser_id: browser_id_for(visit),
        strong_keys: strong_keys_for(visit),
        occurred_at: occurred_at,
        identity_snapshot: identity_snapshot_for(visit)
      )
    rescue StandardError
      nil
    end

    def browser_id_for(visit)
      browser_id = Analytics::BrowserIdentity.current(request)
      return browser_id if browser_id.present?

      visit.browser_id if visit.respond_to?(:has_attribute?) && visit.has_attribute?(:browser_id)
    end

    def strong_keys_for(visit)
      keys = {}
      keys[:identity_id] = visit.user_id if visit.user_id.present?
      keys
    end

    def identity_snapshot_for(visit)
      identity =
        if visit.respond_to?(:user) && visit.user.present?
          visit.user
        elsif Current.identity.present? && Current.identity.id == visit.user_id
          Current.identity
        end

      return {} if identity.blank?

      {
        display_name: identity.display_name,
        email: identity.email
      }
    rescue StandardError
      {}
    end

    def force_new_visit_boundary?
      request.present? && Analytics::VisitBoundary.force_new_visit?(request)
    end
end
