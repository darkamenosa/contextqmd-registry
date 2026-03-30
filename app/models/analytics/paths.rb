# frozen_string_literal: true

class Analytics::Paths
  def initialize(site:, helpers: Rails.application.routes.url_helpers)
    @site = site
    @helpers = helpers
  end

  def shell_paths
    return {} if site.blank?

    {
      reports: reports,
      live: live,
      settings: settings
    }
  end

  def settings_payload_paths
    return {} if site.blank?

    shell_paths.merge(
      settings_data: settings_data,
      google_search_console_connect: google_search_console_connect,
      google_search_console: google_search_console,
      google_search_console_sync: google_search_console_sync
    )
  end

  def reports(dialog: nil)
    path = single_site_mode? ? helpers.admin_analytics_path : helpers.admin_analytics_site_path(site: site.public_id)
    return path if dialog.blank?

    "#{path}/_/#{escape_dialog(dialog)}"
  end

  def live
    single_site_mode? ? helpers.admin_analytics_live_path : helpers.admin_analytics_site_live_path(site: site.public_id)
  end

  def settings
    if single_site_mode?
      helpers.admin_settings_analytics_path
    else
      helpers.admin_settings_analytics_path(site: site.public_id)
    end
  end

  def settings_data
    helpers.settings_data_admin_analytics_site_path(site: site.public_id)
  end

  def google_search_console
    helpers.google_search_console_admin_analytics_site_path(site: site.public_id)
  end

  def google_search_console_connect
    helpers.google_search_console_connect_admin_analytics_site_path(site: site.public_id)
  end

  def google_search_console_sync
    helpers.google_search_console_sync_admin_analytics_site_path(site: site.public_id)
  end

  def google_search_console_callback
    helpers.admin_analytics_google_search_console_callback_path
  end

  private
    attr_reader :site, :helpers

    def single_site_mode?
      ::Analytics::Site.sole_active == site
    end

    def escape_dialog(dialog)
      dialog.to_s.split("/").reject(&:blank?).map { |segment| CGI.escape(segment) }.join("/")
    end
end
