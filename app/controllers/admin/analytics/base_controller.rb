# frozen_string_literal: true

require "digest"
require "cgi"
require "set"

module Admin
  module Analytics
    # Holds shared analytics querying logic so subcontrollers stay thin.
    class BaseController < ::Admin::BaseController
      include GoogleSearchConsoleContext
      include SiteContext

      before_action :prepare_query

      private
        DEFAULT_LIMIT = 100
        MAX_LIMIT = 500
        MAX_SEARCH_LEN = 100
        ALLOWED_PERIODS = %w[realtime day 7d 28d 30d 91d month 6mo 12mo year all custom].freeze

        # Pagination and search helpers
        def parsed_pagination
          lim = params[:limit].to_i
          pg = params[:page].to_i
          lim = DEFAULT_LIMIT if lim <= 0 || lim > MAX_LIMIT
          pg = 1 if pg <= 0
          [ lim, pg ]
        end

        def normalized_search
          term = params[:search].to_s
          s = term.strip
          s = s[0, MAX_SEARCH_LEN]
          s.empty? ? nil : s
        end

        # Parse order_by using model's whitelist/normalization
        def parsed_order_by
          ::Analytics::Ordering.parsed_order_by(params[:order_by])
        end

        def shell_props(query)
          {
            site: site_context,
            query: query_payload(query),
            "defaultQuery" => query_payload(default_query)
          }
        end

        def ensure_canonical_shell_path!(view:, dialog: nil)
          resolution = ::Analytics::AdminSiteResolver.resolve(request: request, explicit_site_id: params[:site])

          if resolution&.site.present?
            paths = ::Analytics::Paths.new(site: resolution.site, helpers: self)
            target = view == :reports ? paths.reports(dialog:) : paths.live
            destination = append_query_string(target)
            return if same_shell_destination?(destination)

            redirect_to destination
          else
            redirect_to admin_settings_analytics_path
          end
        end

        def same_shell_destination?(destination)
          destination == request.fullpath || destination == request.path
        end

        def append_query_string(path)
          return path if request.query_string.blank?

          separator = path.include?("?") ? "&" : "?"
          "#{path}#{separator}#{request.query_string}"
        end

        def dashboard_boot_payload(query, site: site_context)
          top_stats = top_stats_payload(query)
          graph_metric = requested_graph_metric(top_stats)
          graph_interval = requested_graph_interval(top_stats)
          sources_mode = requested_sources_mode(query)
          pages_mode = requested_pages_mode(query)
          locations_mode = requested_locations_mode(query)
          devices_base_mode = requested_devices_base_mode
          devices_mode = requested_devices_mode(query, base_mode: devices_base_mode)
          behaviors_mode = behaviors_available?(site) ? requested_behaviors_mode(site) : nil

          payload = {
            top_stats: top_stats,
            main_graph: main_graph_payload(query.with_options(metric: graph_metric, interval: graph_interval)),
            sources: sources_payload(query.with_option(:mode, sources_mode)),
            pages: pages_payload(query.with_option(:mode, pages_mode)),
            locations: locations_payload(query.with_option(:mode, locations_mode)),
            devices: devices_payload(query.with_option(:mode, devices_mode)),
            ui: {
              graph_metric: graph_metric,
              graph_interval: graph_interval,
              sources_mode: sources_mode,
              pages_mode: pages_mode,
              locations_mode: locations_mode,
              devices_base_mode: devices_base_mode,
              devices_mode: devices_mode,
              behaviors_mode: behaviors_mode,
              behaviors_funnel: requested_behaviors_funnel,
              behaviors_property: requested_behaviors_property
            }
          }

          if behaviors_mode.present?
            payload[:behaviors] =
              if behaviors_mode == "visitors"
                profiles_payload(query)
              else
                behaviors_payload(
                  query.with_options(
                    mode: behaviors_mode,
                    funnel: requested_behaviors_funnel,
                    property: behaviors_mode == "props" ? requested_behaviors_property : nil
                  ).compact
                )
              end
          else
            payload[:behaviors] = nil
          end

          payload
        end

        def prepare_query
          @query = ::Analytics::Query.from_ui_params(
            default_query.ui_attributes.merge(prepared_params(params)),
            dataset: :dashboard,
            order_by: parsed_order_by
          )
        end

        def prepared_params(raw_params)
          ::Analytics::RequestQueryParser.parse(
            query_string: request.query_string,
            params: raw_params,
            allowed_periods: ALLOWED_PERIODS
          )
        end

        def default_query
          ::Analytics::Query.from_ui_params(
            {
              period: "day",
              comparison: nil,
              match_day_of_week: true,
              filters: {},
              labels: {},
              with_imported: false
            }
          )
        end

        def devices_payload(query, limit: nil, page: nil, search: nil)
          payload = ::Analytics::DevicesDatasetQuery.payload(query: query_for_dataset(query, :devices), limit: limit, page: page, search: search)
          attach_list_comparison(payload, query, search:) do |comparison_query|
            ::Analytics::DevicesDatasetQuery.payload(query: query_for_dataset(comparison_query, :devices), limit: MAX_LIMIT, page: 1, search: search)
          end
        end

        def behaviors_payload(query, limit: nil, page: nil, search: nil)
          payload = ::Analytics::BehaviorsDatasetQuery.payload(query: query_for_dataset(query, :behaviors), limit: limit, page: page, search: search)

          if query.comparison.present?
            if payload.is_a?(Hash) && payload[:list].is_a?(Hash)
              list = attach_list_comparison(payload[:list], query, search:) do |comparison_query|
                comparison_payload = ::Analytics::BehaviorsDatasetQuery.payload(query: query_for_dataset(comparison_query, :behaviors), limit: MAX_LIMIT, page: 1, search: search)
                comparison_payload[:list] || comparison_payload
              end
              payload.merge(list: list)
            elsif payload.is_a?(Hash) && payload[:results].is_a?(Array)
              attach_list_comparison(payload, query, search:) do |comparison_query|
                ::Analytics::BehaviorsDatasetQuery.payload(query: query_for_dataset(comparison_query, :behaviors), limit: MAX_LIMIT, page: 1, search: search)
              end
            else
              payload
            end
          else
            payload
          end
        end

        def profiles_payload(query, limit: nil, page: nil, search: nil)
          effective_limit = limit || DEFAULT_LIMIT
          effective_page = page || 1

          AnalyticsProfile.profiles_payload(
            query_for_dataset(query, :profiles),
            limit: effective_limit,
            page: effective_page,
            search: search
          )
        end

        def goals_available?
          ::Analytics::Goals.available?
        end

        def behaviors_available?(site = site_context)
          site[:has_goals] || site[:funnels_available] || site[:props_available] || site[:profiles_available]
        end

        def sources_payload(query, limit: nil, page: nil, search: nil)
          payload = ::Analytics::SourcesDatasetQuery.payload(query: query_for_dataset(query, :sources), limit: limit, page: page, search: search)
          attach_list_comparison(payload, query, search:) do |comparison_query|
            ::Analytics::SourcesDatasetQuery.payload(query: query_for_dataset(comparison_query, :sources), limit: MAX_LIMIT, page: 1, search: search)
          end
        end

        def pages_payload(query, limit: nil, page: nil, search: nil)
          payload = ::Analytics::PagesDatasetQuery.payload(query: query_for_dataset(query, :pages), limit: limit, page: page, search: search)
          payload = attach_list_comparison(payload, query, search:) do |comparison_query|
            ::Analytics::PagesDatasetQuery.payload(query: query_for_dataset(comparison_query, :pages), limit: MAX_LIMIT, page: 1, search: search)
          end

          if ::Analytics::Query.wrap(query).mode.to_s == "seo"
            attach_google_search_console_status_meta(
              payload,
              unsupported_filters: ::Analytics::GoogleSearchConsole.unsupported_pages_filters?(query)
            )
          else
            payload
          end
        end

        def locations_payload(query, limit: nil, page: nil, search: nil)
          payload = ::Analytics::LocationsDatasetQuery.payload(query: query_for_dataset(query, :locations), limit: limit, page: page, search: search)
          attach_list_comparison(payload, query, search:) do |comparison_query|
            ::Analytics::LocationsDatasetQuery.payload(query: query_for_dataset(comparison_query, :locations), limit: MAX_LIMIT, page: 1, search: search)
          end
        end

        def main_graph_payload(query)
          ::Analytics::MainGraphQuery.payload(query: query_for_dataset(query, :main_graph))
        end

        def top_stats_payload(query)
          ::Analytics::TopStatsQuery.payload(query: query_for_dataset(query, :top_stats))
        end

        def search_terms_payload(query, limit:, page:, search: nil)
          ::Analytics::SearchTermsDatasetQuery.payload(
            query: query_for_dataset(query, :search_terms),
            limit: limit,
            page: page,
            search: search,
            order_by: parsed_order_by
          )
        end

        def search_terms_response(query, limit:, page:, search: nil)
          query = ::Analytics::Query.wrap(query)

          if !gsc_configured?
            [ { errorCode: "not_configured", isAdmin: true }, :unprocessable_entity ]
          elsif ::Analytics::GoogleSearchConsole.unsupported_search_terms_filters?(query)
            [ { errorCode: "unsupported_filters" }, :unprocessable_entity ]
          else
            begin
              ensure_google_search_console_search_terms_coverage!(query)

              payload = cache_for([ :search_terms, limit, page, search, params[:order_by], google_search_console_cache_version ]) do
                search_terms_payload(query, limit:, page:, search:)
              end
              payload = attach_list_comparison(payload, query, search:) do |comparison_query|
                ensure_google_search_console_search_terms_coverage!(comparison_query)
                search_terms_payload(comparison_query, limit: MAX_LIMIT, page: 1, search:)
              end
              payload = attach_search_terms_status_meta(payload)

              range, = ::Analytics::Ranges.range_and_interval_for(query.time_range_key, nil, query)
              if payload[:results].blank? && (Time.zone.now - range.begin < 72.hours)
                [ { errorCode: "period_too_recent" }, :unprocessable_entity ]
              else
                [ analytics_json(payload), :ok ]
              end
            rescue ::Analytics::GoogleSearchConsole::Client::Error => e
              [ { errorCode: "request_failed", message: e.message }, :unprocessable_entity ]
            end
          end
        end

        def referrers_payload(query, source, limit: nil, page: nil, search: nil)
          payload = ::Analytics::ReferrersDatasetQuery.payload(query: query_for_dataset(query, :referrers), source: source, limit: limit, page: page, search: search)
          attach_list_comparison(payload, query, search:) do |comparison_query|
            ::Analytics::ReferrersDatasetQuery.payload(query: query_for_dataset(comparison_query, :referrers), source: source, limit: MAX_LIMIT, page: 1, search: search)
          end
        end

        # --- Query helpers ---
        def cache_for(key)
          digest = Digest::SHA256.hexdigest(JSON.dump([ key, ::Analytics::Current.site&.public_id, query_payload(@query), Ahoy::Visit.analytics_data_version ]))
          Rails.cache.fetch([ :analytics, action_name, digest ], expires_in: 5.minutes) { yield }
        end

        def query_payload(query)
          query.respond_to?(:to_h) ? query.to_h : query
        end

        def query_for_dataset(query, dataset)
          ::Analytics::Query.wrap(query).for_dataset(dataset)
        end

        def analytics_json(value)
          ::Analytics::JsonSerializer.call(value)
        end

        def camelize_keys(value)
          analytics_json(value)
        end

        def skip_imported_reason
          @query.with_imported? ? "not_supported" : nil
        end

        def attach_list_comparison(payload, query, search: nil)
          query = ::Analytics::Query.wrap(query)

          if payload.is_a?(Hash) && payload[:results].is_a?(Array) && payload[:results].any? && query.comparison.present?
            source_range, = ::Analytics::Ranges.range_and_interval_for(query.time_range_key, nil, query)
            effective_source_range = ::Analytics::Ranges.trim_range_to_now_if_applicable(source_range, query.time_range_key)
            comparison_range = ::Analytics::Ranges.comparison_range_for(
              query,
              source_range,
              effective_source_range: effective_source_range
            )

            if comparison_range
              comparison_query = query.merge(
                period: "custom",
                comparison: nil,
                match_day_of_week: false,
                date: nil,
                from: comparison_range.begin.to_date.iso8601,
                to: comparison_range.end.to_date.iso8601,
                compare_from: nil,
                compare_to: nil,
                range_override: comparison_range,
                comparison_names: payload[:results].filter_map { |row| row[:name] || row["name"] },
                comparison_codes: payload[:results].filter_map do |row|
                  row[:code] || row["code"] || row[:alpha2] || row["alpha2"] || row[:alpha3] || row["alpha3"]
                end
              )

              comparison_payload = yield(comparison_query)
              comparison_rows = Array(comparison_payload[:results])

              if comparison_rows.any?
                metrics = Array(payload[:metrics]).map(&:to_s)
                indexed_comparison = comparison_rows.index_by { |row| list_comparison_key(row) }
                payload[:results] = payload[:results].map do |row|
                  comparison_row = indexed_comparison[list_comparison_key(row)]

                  comparison_values = {}
                  comparison_changes = {}

                  metrics.each do |metric|
                    current_value = read_metric_value(row, metric)
                    previous_value = comparison_row ? read_metric_value(comparison_row, metric) : 0
                    previous_value = 0 if previous_value.nil? && !current_value.nil?
                    next if current_value.nil? && previous_value.nil?

                    comparison_values[metric.to_sym] = previous_value
                    comparison_changes[metric.to_sym] =
                      ::Analytics::ReportMetrics.top_stat_change(metric, previous_value, current_value)
                  end

                  row.merge(
                    comparison: comparison_values.merge(change: comparison_changes)
                  )
                end

                payload[:meta] = (payload[:meta] || {}).merge(
                  date_range_label: format_range_label(effective_source_range),
                  comparison_date_range_label: format_range_label(comparison_range)
                )
              end
            end
          end

          payload
        end

        def list_comparison_key(row)
          code = row[:code] || row["code"] || row[:alpha2] || row["alpha2"] || row[:alpha3] || row["alpha3"]
          name = row[:name] || row["name"]
          [ code.presence, name.to_s ]
        end

        def read_metric_value(row, metric)
          metric_key = metric.to_s
          camel_key = metric_key.camelize(:lower)
          [ metric_key.to_sym, metric_key, camel_key.to_sym, camel_key ].each do |key|
            return row[key] if row.key?(key)
          end
          nil
        end

        def format_range_label(range)
          return "" unless range

          from = range.begin.in_time_zone
          to = range.end.in_time_zone
          if from.to_date == to.to_date
            from.strftime("%a, %-d %b %Y")
          else
            "#{from.strftime("%-d %b %Y")} - #{to.strftime("%-d %b %Y")}"
          end
        end

        def normalized_ui_param(key)
          value = params[key].to_s.strip
          return nil if value.blank? || %w[undefined null].include?(value)

          value
        end

        def requested_graph_metric(top_stats)
          requested = normalized_ui_param(:graph_metric) || normalized_ui_param(:metric)
          return requested if top_stats[:graphable_metrics].include?(requested)

          top_stats[:graphable_metrics].first || "visitors"
        end

        def requested_graph_interval(top_stats)
          normalized_ui_param(:graph_interval) || normalized_ui_param(:interval) || top_stats[:interval]
        end

        def requested_sources_mode(query)
          requested = normalized_ui_param(:sources_mode) || normalized_ui_param(:mode)
          return requested if requested.in?(%w[channels all utm-medium utm-source utm-campaign utm-content utm-term])

          case normalized_dialog_segment
          when "referrers"
            "all"
          when "channels"
            "channels"
          when "utm-mediums"
            "utm-medium"
          when "utm-sources"
            "utm-source"
          when "utm-campaigns"
            "utm-campaign"
          when "utm-contents"
            "utm-content"
          when "utm-terms"
            "utm-term"
          else
            return "utm-medium" if query.filter_value(:utm_medium).present?
            return "utm-source" if query.filter_value(:utm_source).present?
            return "utm-campaign" if query.filter_value(:utm_campaign).present?
            return "utm-content" if query.filter_value(:utm_content).present?
            return "utm-term" if query.filter_value(:utm_term).present?

            "all"
          end
        end

        def requested_pages_mode(query)
          requested = normalized_ui_param(:pages_mode) || normalized_ui_param(:mode)
          return requested if requested.in?(%w[pages entry exit seo])

          case normalized_dialog_segment
          when "entry-pages"
            "entry"
          when "exit-pages"
            "exit"
          else
            "pages"
          end
        end

        def requested_locations_mode(query)
          requested = normalized_ui_param(:locations_mode) || normalized_ui_param(:mode)
          return requested if requested.in?(%w[map countries regions cities])

          case normalized_dialog_segment
          when "countries", "regions", "cities"
            normalized_dialog_segment
          else
            "map"
          end
        end

        def requested_devices_base_mode
          requested = normalized_ui_param(:devices_mode) || normalized_ui_param(:mode)
          case requested
          when "browsers", "browser-versions"
            return "browsers"
          when "operating-systems", "operating-system-versions"
            return "operating-systems"
          when "screen-sizes"
            return "screen-sizes"
          end

          case normalized_dialog_segment
          when "operating-systems"
            "operating-systems"
          when "screen-sizes"
            "screen-sizes"
          else
            "browsers"
          end
        end

        def requested_devices_mode(query, base_mode: requested_devices_base_mode)
          requested = normalized_ui_param(:devices_mode) || normalized_ui_param(:mode)
          return requested if requested.in?(%w[browser-versions operating-system-versions])

          if base_mode == "browsers" && (query.filter_value(:browser).present? || query.filter_value(:browser_version).present?)
            "browser-versions"
          elsif base_mode == "operating-systems" && (query.filter_value(:os).present? || query.filter_value(:os_version).present?)
            "operating-system-versions"
          else
            base_mode
          end
        end

        def requested_behaviors_mode(site)
          requested = normalized_ui_param(:behaviors_mode) || normalized_ui_param(:mode)
          allowed =
            if site[:has_goals]
              %w[conversions props funnels visitors]
            else
              %w[props funnels visitors]
            end

          return requested if allowed.include?(requested)
          return "visitors" if site[:profiles_available]
          return "conversions" if site[:has_goals]
          return "props" if site[:props_available]
          return "funnels" if site[:funnels_available]

          nil
        end

        def requested_behaviors_funnel
          normalized_ui_param(:behaviors_funnel) || normalized_ui_param(:funnel)
        end

        def requested_behaviors_property
          normalized_ui_param(:behaviors_property) || normalized_ui_param(:property)
        end

        def normalized_dialog_segment
          raw = request.path.to_s[%r{/admin/analytics(?:/reports)?/_/([^/?#]+)}, 1]
          return nil if raw.blank?

          case raw
          when "utm_mediums", "utm-mediums", "utm-medium"
            "utm-mediums"
          when "utm_sources", "utm-sources", "utm-source"
            "utm-sources"
          when "utm_campaigns", "utm-campaigns", "utm-campaign"
            "utm-campaigns"
          when "utm_contents", "utm-contents", "utm-content"
            "utm-contents"
          when "utm_terms", "utm-terms", "utm-term"
            "utm-terms"
          when "entry_pages", "entry-pages", "entry"
            "entry-pages"
          when "exit_pages", "exit-pages", "exit"
            "exit-pages"
          when "operating_systems", "operating-systems"
            "operating-systems"
          when "screen_sizes", "screen-sizes"
            "screen-sizes"
          else
            raw.tr("_", "-")
          end
        end
    end
  end
end
