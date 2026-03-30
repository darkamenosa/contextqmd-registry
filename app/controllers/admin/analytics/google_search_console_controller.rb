# frozen_string_literal: true

module Admin
  module Analytics
    class GoogleSearchConsoleController < BaseController
      skip_before_action :prepare_query
      skip_before_action :resolve_analytics_site, only: :callback
      before_action :ensure_google_search_console_available, only: [ :connect, :callback, :sync ]
      before_action :set_google_search_console_connection, only: [ :update, :destroy, :sync ]

      def connect
        if ::Analytics::Current.site.blank?
          redirect_to admin_settings_analytics_path, alert: "Initialize analytics before connecting Google Search Console."
          return
        end

        state = SecureRandom.hex(24)
        session[google_search_console_oauth_state_key] = {
          "state" => state,
          "site_id" => ::Analytics::Current.site.public_id
        }

        redirect_to google_search_console_client.authorization_url(state: state), allow_other_host: true
      end

      def callback
        oauth_context = consume_google_oauth_context
        site = resolve_google_oauth_site(oauth_context)

        if params[:error].present?
          redirect_to_google_search_console_settings(site, alert: google_oauth_error_message)
          return
        end

        if params[:code].blank?
          redirect_to_google_search_console_settings(site, alert: "Google Search Console did not return an authorization code.")
          return
        end

        unless valid_google_oauth_state?(oauth_context)
          redirect_to_google_search_console_settings(site, alert: "Google Search Console connection could not be verified.")
          return
        end

        if site.blank?
          redirect_to admin_settings_analytics_path, alert: "Analytics site could not be resolved for this Google Search Console connection."
          return
        end

        ::Analytics::Current.site = site
        ::Analytics::Current.site_boundary = site.boundaries.find_by(primary: true)

        token_payload = google_search_console_client.exchange_code!(params[:code].to_s)
        access_token = token_payload.fetch("access_token")
        refresh_token = token_payload["refresh_token"].to_s
        if refresh_token.blank?
          redirect_to_google_search_console_settings(site, alert: "Google did not return a refresh token. Remove the app from your Google account and try connecting again.")
          return
        end
        scopes = normalize_google_search_console_scopes(token_payload["scope"])
        expires_at = token_payload["expires_in"].to_i.seconds.from_now if token_payload["expires_in"].present?
        profile = google_search_console_client.fetch_user_profile(access_token)
        properties = google_search_console_client.list_verified_properties(access_token)

        connection = ::Analytics::GoogleSearchConsoleConnection.rotate_for_site!(
          site: site,
          attributes: {
            google_uid: profile["sub"],
            google_email: profile["email"].to_s.downcase,
            access_token: access_token,
            refresh_token: refresh_token,
            expires_at: expires_at,
            scopes: scopes,
            metadata: {}
          }
        )

        auto_selected_property = properties.one? ? properties.first : nil
        connection.store_property!(auto_selected_property) if auto_selected_property.present?
        enqueue_google_search_console_sync(connection) if connection.configured?

        notice =
          if properties.empty?
            "Connected Google Search Console, but Google did not return any verified properties for this account."
          elsif auto_selected_property.present?
            "Connected Google Search Console and selected #{auto_selected_property.fetch(:label)}."
          else
            "Connected Google Search Console. Select a property to finish setup."
          end

        redirect_to_google_search_console_settings(site, notice: notice)
      rescue ::Analytics::GoogleSearchConsole::Client::Error => e
        redirect_to_google_search_console_settings(site, alert: e.message)
      end

      def update
        permitted = params.expect(google_search_console: [ :property_identifier ])
        property_identifier = permitted.fetch(:property_identifier).to_s
        property = verified_google_search_console_properties(@google_search_console_connection).find do |candidate|
          candidate.fetch(:identifier) == property_identifier
        end

        if property.blank?
          redirect_to analytics_settings_paths.fetch(:settings), alert: "Select a verified Search Console property."
          return
        end

        @google_search_console_connection.store_property!(property)
        enqueue_google_search_console_sync(@google_search_console_connection)

        redirect_to analytics_settings_paths.fetch(:settings), notice: "Updated Google Search Console property to #{property.fetch(:label)}."
      rescue ::Analytics::GoogleSearchConsole::Client::Error => e
        redirect_to analytics_settings_paths.fetch(:settings), alert: e.message
      end

      def destroy
        @google_search_console_connection.disconnect!

        redirect_to analytics_settings_paths.fetch(:settings), notice: "Disconnected Google Search Console."
      end

      def sync
        unless @google_search_console_connection.configured?
          redirect_to analytics_settings_paths.fetch(:settings), alert: "Select a verified Search Console property first."
          return
        end

        from_date, to_date = manual_sync_window(@google_search_console_connection)

        if ::Analytics::GoogleSearchConsole::Sync.running_covering?(
          connection: @google_search_console_connection,
          from_date: from_date,
          to_date: to_date,
          search_type: ::Analytics::GoogleSearchConsole::Syncer::DEFAULT_SEARCH_TYPE
        )
          redirect_to analytics_settings_paths.fetch(:settings), notice: "A Google Search Console sync is already in progress."
          return
        end

        ::Analytics::GoogleSearchConsoleSyncJob.perform_later(
          @google_search_console_connection.id,
          from_date: from_date.iso8601,
          to_date: to_date.iso8601
        )

        redirect_to analytics_settings_paths.fetch(:settings), notice: "Queued a Google Search Console sync."
      end

      private
        def ensure_google_search_console_available
          return if ::Analytics::GoogleSearchConsole::Configuration.configured?

          redirect_to analytics_settings_paths.fetch(:settings), alert: "Google Search Console is not configured for this environment."
        end

        def set_google_search_console_connection
          @google_search_console_connection = current_google_search_console_connection
          return if @google_search_console_connection.present?

          redirect_to analytics_settings_paths.fetch(:settings), alert: "Connect Google Search Console first."
        end

        def google_search_console_oauth_state_key
          :analytics_gsc_oauth_state
        end

        def consume_google_oauth_context
          session.delete(google_search_console_oauth_state_key)
        end

        def valid_google_oauth_state?(oauth_context)
          expected = oauth_context.is_a?(Hash) ? oauth_context["state"].to_s : oauth_context.to_s
          actual = params[:state].to_s
          expected.present? && actual.present? && ActiveSupport::SecurityUtils.secure_compare(expected, actual)
        end

        def resolve_google_oauth_site(oauth_context)
          site_id = oauth_context.is_a?(Hash) ? oauth_context["site_id"].to_s : nil
          return if site_id.blank?

          ::Analytics::Site.active.find_by(public_id: site_id)
        end

        def google_oauth_error_message
          return "Google Search Console connection was canceled." if params[:error].to_s == "access_denied"

          "Google Search Console connection failed."
        end

        def normalize_google_search_console_scopes(scope_value)
          Array(scope_value.to_s.split(/\s+/).map(&:strip).reject(&:blank?)).uniq
        end

        def enqueue_google_search_console_sync(connection)
          from_date, to_date = ::Analytics::GoogleSearchConsole::Syncer.default_sync_window
          return if to_date < from_date

          ::Analytics::GoogleSearchConsoleSyncJob.perform_later(
            connection.id,
            from_date: from_date.iso8601,
            to_date: to_date.iso8601
          )
        end

        def manual_sync_window(connection)
          successful_sync = connection.syncs.successful.where(property_identifier: connection.property_identifier).latest_first.first
          return ::Analytics::GoogleSearchConsole::Syncer.default_sync_window if successful_sync.blank?

          ::Analytics::GoogleSearchConsole::Syncer.refresh_sync_window
        end

        def redirect_to_google_search_console_settings(site, notice: nil, alert: nil)
          path =
            if site.present?
              ::Analytics::Paths.new(site:, helpers: self).settings
            else
              admin_settings_analytics_path
            end

          redirect_to path, notice:, alert:
        end
    end
  end
end
