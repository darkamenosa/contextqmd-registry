require Rails.root.join("lib/client_ip")

class Ahoy::Store < Ahoy::DatabaseStore
  def visit_columns
    super + %i[hostname screen_size browser_version]
  end

  def track_visit(data)
    data = data.with_indifferent_access
    attrs = data.dup

    req = Current.request
    if req
      attrs[:hostname] ||= req.host

      # Prefer the real landing page, not the Ahoy API endpoint
      begin
        lp = attrs[:landing_page].to_s
        if lp.blank? || internal_path?(lp)
          attrs[:landing_page] = req.referer if req.referer.present?
        end
      rescue StandardError
        # never block tracking
      end

      # Best-effort referrer domain
      if req.referer.present?
        begin
          ref_host = URI.parse(req.referer).host
          host = attrs[:hostname].presence || req.host
          if local_host?(ref_host) || same_site_host?(ref_host, host)
            attrs[:referrer] = nil if attrs[:referrer].to_s == req.referer
            attrs[:referring_domain] = nil
          else
            attrs[:referring_domain] ||= ref_host
          end
        rescue URI::InvalidURIError
          # ignore
        end
      end

      if defined?(MaxmindGeo) && MaxmindGeo.available?
        if (record = lookup_maxmind_record(req, data))
          attrs[:country] ||= record[:country_iso]
          attrs[:region] ||= record[:subdivisions]&.first
          attrs[:city] ||= record[:city]
          attrs[:latitude] ||= record[:latitude]
          attrs[:longitude] ||= record[:longitude]
        end
      end

      # Cloudflare country fallback
      cc = ClientIp.country_hint(req)
      attrs[:country] ||= cc if cc
    else
      begin
        lp = (attrs[:landing_page] || data[:landing_page]).to_s
        if lp.present?
          attrs[:hostname] ||= URI.parse(lp).host
        end
      rescue URI::InvalidURIError
        # ignore
      end
    end

    result = super(attrs)

    # Post-create cleanup
    begin
      token = data[:visit_token]
      v = token.present? ? ::Ahoy::Visit.find_by(visit_token: token) : nil
      if v
        req_host = Current.request&.host
        if v.hostname.blank? && req_host.present?
          v.update_column(:hostname, req_host)
        end
        site_host = v.hostname.presence || req_host
        if local_host?(v.referring_domain) || same_site_host?(v.referring_domain, site_host)
          v.update_columns(referrer: nil, referring_domain: nil)
        end
      end
    rescue StandardError
      # never block tracking
    end

    result
  end

  def track_event(data)
    data = data.with_indifferent_access
    result = super(data)

    # Extract screen_size from viewport string
    props = data[:properties].to_h.with_indifferent_access
    raw_size = props[:screen_size]
    if raw_size.present?
      token = data[:visit_token]
      if token.present?
        if (v = ::Ahoy::Visit.find_by(visit_token: token)) && v.screen_size.blank?
          bucket = classify_viewport(raw_size)
          v.update_column(:screen_size, bucket) if bucket.present?
        end
      end
    end

    # Correct landing_page when visit was created with API path
    begin
      event = result.is_a?(::Ahoy::Event) ? result : nil
      event_props = event&.properties.to_h.with_indifferent_access
      data_props = data[:properties].to_h.with_indifferent_access
      url = event_props[:url] || data_props[:url]

      visit = event&.visit
      if visit.nil?
        token = data[:visit_token]
        visit = ::Ahoy::Visit.find_by(visit_token: token) if token.present?
      end

      if visit && url.present?
        lp = visit.landing_page.to_s
        needs_fix = lp.blank? || internal_path?(lp)
        visit.update_column(:landing_page, url) if needs_fix
      end
    rescue StandardError
      # never block ingestion
    end

    result
  end

  private
    def internal_path?(value)
      return false if value.blank?
      path = begin
        URI.parse(value).path
      rescue URI::InvalidURIError
        value.to_s
      end.to_s
      path.start_with?("/ahoy", "/cable", "/rails/", "/assets/", "/up", "/jobs", "/webhooks")
    end

    def same_site_host?(ref_host, site_host)
      return false if ref_host.to_s.strip.empty? || site_host.to_s.strip.empty?
      a = ref_host.to_s.downcase.sub(/^www\./, "")
      b = site_host.to_s.downcase.sub(/^www\./, "")
      a == b
    end

    def local_host?(host)
      h = host.to_s.downcase
      return true if h == "localhost"
      begin
        ip = IPAddr.new(h) rescue nil
        return true if ip && (ip.loopback? || ip.to_s == "0.0.0.0" || ip.to_s == "::1")
      rescue StandardError
      end
      false
    end

    def classify_viewport(raw_size)
      return nil if raw_size.blank?
      parts = raw_size.to_s.split("x")
      return nil unless parts.size == 2
      width = parts[0].to_i
      return nil if width <= 0
      if width < 576
        "Mobile"
      elsif width < 992
        "Tablet"
      elsif width < 1440
        "Laptop"
      else
        "Desktop"
      end
    end

    def lookup_maxmind_record(req, data)
      client_ip = ClientIp.public(req, fallback_ip: data[:ip])
      client_ip ? MaxmindGeo.lookup(client_ip) : nil
    end
end

# JavaScript tracking enabled
Ahoy.api = true
Ahoy.cookies = :none
Ahoy.mask_ips = true
Ahoy.track_bots = false
Ahoy.geocode = false
Ahoy.visit_duration = 30.minutes
Ahoy.quiet = false
Ahoy.server_side_visits = :when_needed

Ahoy.exclude_method = lambda do |controller, request|
  req = request || controller&.request
  return true if req.nil?
  path = req.path.to_s

  # Allow Ahoy API events/visits to be recorded
  return false if path.start_with?("/ahoy")

  # Exclude admin area and internal paths
  path.start_with?("/admin", "/rails/", "/assets/", "/up", "/jobs", "/webhooks")
end

# Ensure Ahoy controllers skip CSRF
Rails.application.config.to_prepare do
  if defined?(Ahoy::VisitsController)
    Ahoy::VisitsController.skip_forgery_protection
    Ahoy::VisitsController.around_action do |controller, action|
      Current.set(request: controller.request) { action.call }
    end
  end
  if defined?(Ahoy::EventsController)
    Ahoy::EventsController.skip_forgery_protection
    Ahoy::EventsController.around_action do |controller, action|
      Current.set(request: controller.request) { action.call }
    end
  end
end
