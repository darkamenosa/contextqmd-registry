# frozen_string_literal: true

require "digest"
require "cgi"
require "set"

module Admin
  module Analytics
    # Holds shared analytics querying logic so subcontrollers stay thin.
    class BaseController < ::Admin::BaseController
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
          Ahoy::Visit.parsed_order_by(params[:order_by])
        end

        def shell_props(query)
          {
            site: site_context,
            user: user_context,
            query: query,
            "defaultQuery" => default_query
          }
        end

        def prepare_query
          @query = default_query.merge(prepared_params(params))
        end

        def prepared_params(raw_params)
          labels = parse_labels_from_params
          filters, advanced_filters = parse_filters_from_params(raw_params)
          match_day_of_week = if raw_params.key?(:match_day_of_week) || raw_params.key?("match_day_of_week")
            ActiveModel::Type::Boolean.new.cast(raw_params[:match_day_of_week])
          end
          # Map numeric city id -> label if available
          if (city = filters["city"]).present? && city =~ /^\d+$/ && labels[city].present?
            filters["city"] = labels[city]
            labels["city"] = labels[city]
            labels.delete(city)
          end

          # Accept ISO 3166-2 region codes (e.g., "US-CA"). Use label if provided.
          if (region_code = filters["region"]).present? && region_code =~ /^[A-Za-z]{2}-[A-Za-z0-9]{1,3}$/
            if labels["region"].present?
              filters["region"] = labels["region"]
            end
          end

          per = raw_params[:period]
          per = "day" unless ALLOWED_PERIODS.include?(per.to_s)

          {
            period: per,
            comparison: (raw_params[:comparison].to_s == "off" ? nil : raw_params[:comparison]),
            match_day_of_week: match_day_of_week,
            date: raw_params[:date],
            from: raw_params[:from],
            to: raw_params[:to],
            compare_from: raw_params[:compare_from],
            compare_to: raw_params[:compare_to],
            metric: raw_params[:metric],
            interval: raw_params[:interval],
            mode: raw_params[:mode],
            funnel: raw_params[:funnel],
            dialog: raw_params[:dialog],
            with_imported: ActiveModel::Type::Boolean.new.cast(raw_params[:with_imported]),
            filters: filters,
            labels: labels,
            advanced_filters: advanced_filters
          }.compact
        end

        def parse_filters_from_params(raw_params)
          cgi_map = CGI.parse(request.query_string.to_s)
          list = Array(cgi_map["f"])
          f = raw_params[:f]
          list |= Array(f).compact if f.present?
          return [ {}, [] ] if list.empty?

          filters = {}
          advanced = []
          list.each do |token|
            parts = token.to_s.split(",", 3)
            next if parts.length < 3
            op = parts[0].to_s
            dim = parts[1].to_s
            clause = parts[2].to_s
            next if dim.blank? || clause.blank?
            if op == "is"
              if dim == "event:goal" || dim == "goal"
                filters["goal"] = clause
              else
                filters[dim] = clause
              end
            elsif [ "is_not", "contains" ].include?(op)
              advanced << [ op, dim, clause ]
            end
          end
          [ filters, advanced ]
        end

        def parse_labels_from_params
          cgi_map = CGI.parse(request.query_string.to_s)
          list = Array(cgi_map["l"])
          labels = {}
          list.each do |token|
            key, value = token.to_s.split(",", 2)
            next if key.blank? || value.blank?
            labels[key] = value
          end
          labels
        end

        def default_query
          {
            period: "day",
            comparison: nil,
            match_day_of_week: true,
            filters: {},
            labels: {},
            with_imported: false
          }
        end

        def site_context
          {
            domain: request.host,
            timezone: Time.zone.name,
            has_goals: goals_available?,
            has_props: true,
            funnels_available: true,
            props_available: true,
            segments: SEGMENTS,
            flags: {
              dbip: defined?(MaxmindGeo) && MaxmindGeo.available?
            }
          }
        end

        def user_context
          {
            role: "super_admin",
            email: Current.identity&.email
          }
        end

        def devices_payload(query, limit: nil, page: nil, search: nil)
          Ahoy::Visit.devices_payload(query, limit: limit, page: page, search: search, order_by: parsed_order_by)
        end

        def behaviors_payload(query, limit: nil, page: nil, search: nil)
          Ahoy::Visit.behaviors_payload(query, limit: limit, page: page, search: search, order_by: parsed_order_by)
        end

        def goals_available?
          Ahoy::Event.where.not(name: [ "pageview", "engagement" ]).exists?
        end

        def behaviors_available?(site = site_context)
          site[:has_goals] || site[:funnels_available] || site[:props_available]
        end

        def sources_payload(query, limit: nil, page: nil, search: nil)
          Ahoy::Visit.sources_payload(query, limit: limit, page: page, search: search, order_by: parsed_order_by)
        end

        def pages_payload(query, limit: nil, page: nil, search: nil)
          Ahoy::Visit.pages_payload(query, limit: limit, page: page, search: search, order_by: parsed_order_by)
        end

        def locations_payload(query, limit: nil, page: nil, search: nil)
          Ahoy::Visit.locations_payload(query, limit: limit, page: page, search: search, order_by: parsed_order_by)
        end

        def main_graph_payload(query)
          Ahoy::Visit.main_graph_payload(query)
        end

        def top_stats_payload(query)
          Ahoy::Visit.top_stats_payload(query)
        end

        def search_terms_payload(query, limit:, page:, search: nil)
          Ahoy::Visit.search_terms_payload(query, limit: limit, page: page, search: search, order_by: parsed_order_by)
        end

        def search_terms_response(query, limit:, page:, search: nil)
          unless gsc_configured?
            return [ { errorCode: "not_configured", isAdmin: true }, :unprocessable_entity ]
          end
          if unsupported_gsc_filters?(query)
            return [ { errorCode: "unsupported_filters" }, :unprocessable_entity ]
          end

          payload = cache_for([ :search_terms, limit, page, search, params[:order_by] ]) do
            search_terms_payload(query, limit:, page:, search:)
          end

          range, = Ahoy::Visit.range_and_interval_for(query[:period], nil, query)
          if payload[:results].blank? && (Time.zone.now - range.begin < 72.hours)
            return [ { errorCode: "period_too_recent" }, :unprocessable_entity ]
          end

          [ camelize_keys(payload), :ok ]
        end

        def referrers_payload(query, source, limit: nil, page: nil, search: nil)
          Ahoy::Visit.referrers_payload(query, source, limit: limit, page: page, search: search, order_by: parsed_order_by)
        end

        def gsc_configured?
          # Prefer DB flag when available, then Rails config, then ENV
          db = AnalyticsSetting.get_bool("gsc_configured", fallback: nil)
          return db unless db.nil?

          v = Rails.configuration.x.analytics&.gsc_configured
          v = ENV["ANALYTICS_GSC_CONFIGURED"] if v.nil?
          ActiveModel::Type::Boolean.new.cast(v)
        end

        def unsupported_gsc_filters?(query)
          filters = (query[:filters] || {}).stringify_keys
          disallowed = %w[channel referrer utm_source utm_medium utm_campaign utm_content utm_term entry_page exit_page]
          return true if filters.keys.any? { |k| disallowed.include?(k) }

          Array(query[:advanced_filters]).any?
        end

        # --- Query helpers ---
        def cache_for(key)
          digest = Digest::SHA256.hexdigest(JSON.dump([ key, @query, Ahoy::Visit.analytics_data_version ]))
          Rails.cache.fetch([ :analytics, action_name, digest ], expires_in: 5.minutes) { yield }
        end

        def camelize_keys(value)
          case value
          when Array
            value.map { |item| camelize_keys(item) }
          when Hash
            value.each_with_object({}) do |(key, val), memo|
              memo[key.to_s.camelize(:lower)] = camelize_keys(val)
            end
          else
            value
          end
        end

        def skip_imported_reason
          @query[:with_imported] ? "not_supported" : nil
        end

        SEGMENTS = [
          { id: "all", name: "All visitors" }
        ].freeze
    end
  end
end
