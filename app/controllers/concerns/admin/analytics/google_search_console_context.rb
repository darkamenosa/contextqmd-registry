# frozen_string_literal: true

module Admin
  module Analytics
    module GoogleSearchConsoleContext
      extend ActiveSupport::Concern

      private
        def analytics_settings_payload
          {
            gsc_configured: gsc_configured?,
            goals: ::Analytics::Goals.available_names,
            goal_definitions: ::Analytics::Goal.definition_payloads,
            allowed_event_props: ::Analytics::Properties.available_keys,
            google_search_console: google_search_console_payload,
            tracker: analytics_tracker_payload
          }
        end

        def gsc_configured?
          current_google_search_console_connection&.configured? || false
        end

        def current_google_search_console_connection
          @current_google_search_console_connection ||= ::Analytics::GoogleSearchConsoleConnection.current_for(::Analytics::Current.site)
        end

        def google_search_console_payload
          connection = current_google_search_console_connection
          latest_sync = current_google_search_console_sync(connection)
          refresh_from, refresh_to = google_search_console_refresh_sync_window
          properties = []
          properties_error = nil

          if connection.present?
            begin
              properties = verified_google_search_console_properties(connection)
            rescue ::Analytics::GoogleSearchConsole::Client::Error => e
              properties_error = e.message
            end
          end

          {
            available: ::Analytics::GoogleSearchConsole::Configuration.configured?,
            connected: connection.present?,
            configured: connection&.configured? || false,
            callback_path: analytics_google_search_console_callback_path,
            callback_url: analytics_google_search_console_callback_url,
            account_email: connection&.google_email,
            property_identifier: connection&.property_identifier,
            property_type: connection&.property_type,
            permission_level: connection&.permission_level,
            connected_at: connection&.connected_at,
            last_verified_at: connection&.last_verified_at,
            sync_status: latest_sync&.status,
            sync_error: latest_sync&.error_message,
            sync_in_progress: google_search_console_sync_in_progress?(connection, from_date: refresh_from, to_date: refresh_to),
            sync_stale: google_search_console_sync_stale?(connection, from_date: refresh_from, to_date: refresh_to),
            last_synced_at: latest_sync&.finished_at,
            synced_from: latest_sync&.from_date,
            synced_to: latest_sync&.to_date,
            refresh_window_from: refresh_from,
            refresh_window_to: refresh_to,
            properties_error: properties_error,
            properties: properties
          }
        end

        def verified_google_search_console_properties(connection = current_google_search_console_connection)
          return [] if connection.blank?

          access_token = google_search_console_access_token_for(connection)
          google_search_console_client.list_verified_properties(access_token)
        end

        def google_search_console_access_token_for(connection = current_google_search_console_connection)
          return if connection.blank?

          connection.active_access_token!(client: google_search_console_client)
        end

        def google_search_console_client
          @google_search_console_client ||= ::Analytics::GoogleSearchConsole::Client.new(
            redirect_uri: analytics_google_search_console_callback_url
          )
        end

        def analytics_settings_paths
          analytics_paths.settings_payload_paths
        end

        def analytics_tracker_payload
          ::Analytics::TrackerSnippet.build(site: ::Analytics::Current.site, request: request)
        end

        def analytics_google_search_console_callback_path
          ::Analytics::Configuration.google_search_console_callback_path
        end

        def analytics_google_search_console_callback_url
          "#{request.base_url}#{analytics_google_search_console_callback_path}"
        end

        def current_google_search_console_sync(connection = current_google_search_console_connection)
          return if connection.blank?

          @current_google_search_console_sync ||= {}
          @current_google_search_console_sync[connection.id] ||= ::Analytics::GoogleSearchConsole::Sync.latest_for(connection)
        end

        def google_search_console_cache_version
          [
            current_google_search_console_connection&.updated_at&.to_i,
            current_google_search_console_sync&.updated_at&.to_i
          ].compact.max
        end

        def ensure_google_search_console_search_terms_coverage!(query)
          connection = current_google_search_console_connection
          return if connection.blank? || connection.property_identifier.blank?

          from_date, to_date = google_search_console_search_terms_sync_window(query)
          return if from_date.blank? || to_date.blank? || to_date < from_date

          ::Analytics::GoogleSearchConsole::Syncer.ensure_covered!(
            connection: connection,
            from_date: from_date,
            to_date: to_date,
            client: google_search_console_client
          )
        end

        def google_search_console_search_terms_sync_window(query)
          range, = ::Analytics::Ranges.range_and_interval_for(query.time_range_key, nil, query)
          from_date = range.begin.to_date
          to_date = [ range.end.to_date, (Time.zone.today - 3.days) ].min
          [ from_date, to_date ]
        end

        def google_search_console_refresh_sync_window
          ::Analytics::GoogleSearchConsole::Syncer.refresh_sync_window
        end

        def google_search_console_report_status_payload(connection = current_google_search_console_connection, unsupported_filters: false)
          refresh_from, refresh_to = google_search_console_refresh_sync_window
          latest_sync = current_google_search_console_sync(connection)

          {
            connected: connection.present?,
            configured: connection&.configured? || false,
            unsupported_filters: unsupported_filters,
            sync_status: latest_sync&.status,
            sync_error: latest_sync&.error_message,
            sync_in_progress: google_search_console_sync_in_progress?(connection, from_date: refresh_from, to_date: refresh_to),
            sync_stale: google_search_console_sync_stale?(connection, from_date: refresh_from, to_date: refresh_to),
            last_synced_at: latest_sync&.finished_at,
            synced_from: latest_sync&.from_date,
            synced_to: latest_sync&.to_date,
            refresh_window_from: refresh_from,
            refresh_window_to: refresh_to
          }
        end

        def attach_search_terms_status_meta(payload)
          attach_google_search_console_status_meta(payload)
        end

        def attach_google_search_console_status_meta(payload, unsupported_filters: false)
          payload.deep_dup.tap do |result|
            result[:meta] ||= {}
            result[:meta][:search_console] = google_search_console_report_status_payload(
              unsupported_filters: unsupported_filters
            )
          end
        end

        def google_search_console_sync_in_progress?(connection, from_date:, to_date:)
          return false if connection.blank? || to_date < from_date

          ::Analytics::GoogleSearchConsole::Sync.running_covering?(
            connection: connection,
            from_date: from_date,
            to_date: to_date,
            search_type: ::Analytics::GoogleSearchConsole::Syncer::DEFAULT_SEARCH_TYPE
          )
        end

        def google_search_console_sync_stale?(connection, from_date:, to_date:)
          return false if connection.blank? || !connection.configured? || to_date < from_date
          return false if google_search_console_sync_in_progress?(connection, from_date:, to_date:)

          !::Analytics::GoogleSearchConsole::Sync.successful_covering?(
            connection: connection,
            from_date: from_date,
            to_date: to_date,
            search_type: ::Analytics::GoogleSearchConsole::Syncer::DEFAULT_SEARCH_TYPE
          )
        end
    end
  end
end
