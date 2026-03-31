# frozen_string_literal: true

module Ahoy::Visit::AnalyticsIngest
  def needs_event_repair?(site_token: nil)
    return true if site_token.present?
    return true if landing_page_needs_repair?
    return true if hostname.blank?
    return true if screen_size.blank?
    return true if analytics_site_id.blank?
    return true if technology_missing?

    false
  end

  def should_resolve_profile_for_event?(strong_keys: {})
    return true if analytics_profile_id.blank?
    return true if strong_keys.present?

    false
  end

  def analytics_strong_keys
    {}.tap do |keys|
      keys[:identity_id] = user_id if user_id.present?
    end
  end

  def analytics_identity_snapshot
    identity =
      if respond_to?(:user) && user.present?
        user
      end

    if identity.present?
      {
        display_name: identity.display_name,
        email: identity.email
      }
    else
      {}
    end
  rescue StandardError
    {}
  end

  def technology_missing?
    browser.blank? ||
      browser_version.blank? ||
      os.blank? ||
      os_version.blank? ||
      device_type.blank?
  end

  def landing_page_needs_repair?
    landing_page_value = landing_page.to_s
    landing_page_value.blank? || Analytics::InternalPaths.report_internal_path?(normalized_landing_page_path(landing_page_value))
  end

  private
    def normalized_landing_page_path(value)
      URI.parse(value).path
    rescue URI::InvalidURIError
      value.to_s
    end
end
