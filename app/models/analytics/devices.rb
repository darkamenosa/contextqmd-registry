# frozen_string_literal: true

module Analytics::Devices
  class << self
    def categorize_screen_size(screen_size)
      return "(not set)" if screen_size.blank?

      if screen_size =~ /^(\d+)x(\d+)$/
        width = Regexp.last_match(1).to_i
        case width
        when 0...576 then "Mobile"
        when 576...992 then "Tablet"
        when 992...1440 then "Laptop"
        else "Desktop"
        end
      else
        screen_size
      end
    end

    def goal_denominator_counts(query, mode:, search: nil)
      base_query = Analytics::Query.wrap(query)
        .without_goal_or_properties(property_filter: ->(key) { Analytics::Properties.filter_key?(key) })
        .with_option(:mode, mode)

      Analytics::DevicesDatasetQuery.payload(query: base_query, search: search).fetch(:results, []).each_with_object({}) do |row, counts|
        counts[row[:name].to_s] = row[:visitors].to_i
      end
    end

    def formatted_name(name)
      name.to_s.presence || Ahoy::Visit::Constants::UNKNOWN_LABEL
    end

    def grouping_for_mode(mode)
      case mode
      when "browser-versions"
        {
          column: :browser_version,
          base_column: :browser,
          meta_key: :browser,
          search_column_sql: "browser_version",
          group_sql: "browser, browser_version",
          select_sql: "browser, browser_version, ARRAY_AGG(ahoy_visits.id)"
        }
      when "operating-system-versions"
        {
          column: :os_version,
          base_column: :os,
          meta_key: :os,
          search_column_sql: "os_version",
          group_sql: "os, os_version",
          select_sql: "os, os_version, ARRAY_AGG(ahoy_visits.id)"
        }
      when "operating-systems"
        {
          column: :os,
          search_column_sql: "os",
          group_sql: "os",
          select_sql: "os, ARRAY_AGG(ahoy_visits.id)"
        }
      else
        {
          column: :browser,
          search_column_sql: "browser",
          group_sql: "browser",
          select_sql: "browser, ARRAY_AGG(ahoy_visits.id)"
        }
      end
    end

    def apply_search(scope, grouping, pattern)
      case grouping.fetch(:column)
      when :browser_version
        scope.where([ "LOWER(browser_version) LIKE ?", pattern ])
      when :os_version
        scope.where([ "LOWER(os_version) LIKE ?", pattern ])
      when :os
        scope.where([ "LOWER(os) LIKE ?", pattern ])
      else
        scope.where([ "LOWER(browser) LIKE ?", pattern ])
      end
    end

    def pluck_group_rows(scope, grouping)
      case grouping.fetch(:column)
      when :browser_version
        scope.group(Arel.sql("browser, browser_version"))
          .pluck(Arel.sql("browser, browser_version, ARRAY_AGG(ahoy_visits.id)"))
      when :os_version
        scope.group(Arel.sql("os, os_version"))
          .pluck(Arel.sql("os, os_version, ARRAY_AGG(ahoy_visits.id)"))
      when :os
        scope.group(Arel.sql("os"))
          .pluck(Arel.sql("os, ARRAY_AGG(ahoy_visits.id)"))
      else
        scope.group(Arel.sql("browser"))
          .pluck(Arel.sql("browser, ARRAY_AGG(ahoy_visits.id)"))
      end
    end

    def build_result(name:, group_metadata:, metrics:)
      metadata = group_metadata[name] || {}
      metadata.merge(name: metadata[:display_name] || name).merge(metrics)
    end

    def disambiguate_versions?(grouping, filters)
      case grouping.fetch(:column)
      when :browser_version
        filters["browser"].blank?
      when :os_version
        filters["os"].blank?
      else
        false
      end
    end

    def normalize_grouped_visit_ids(rows, meta_key: nil, disambiguate_by_meta: false)
      grouped = Hash.new { |hash, key| hash[key] = [] }
      metadata = {}
      duplicate_versions = Hash.new { |hash, key| hash[key] = [] }

      if disambiguate_by_meta
        rows.each do |row|
          next unless row.length == 3

          base_name, name, = row
          version_name = formatted_name(name)
          base_label = formatted_name(base_name)
          duplicate_versions[version_name] << base_label unless duplicate_versions[version_name].include?(base_label)
        end
      end

      rows.each do |row|
        if row.length == 3
          base_name, name, visit_ids = row
          display_name =
            if disambiguate_by_meta &&
                duplicate_versions[formatted_name(name)].size > 1 &&
                base_name.present?
              formatted_name("#{base_name} #{name}")
            else
              formatted_name(name)
            end

          label = display_name
          grouped[label].concat(Array(visit_ids))
          next if base_name.blank? || meta_key.blank?

          metadata[label] ||= {}
          metadata[label][:display_name] ||= display_name
          metadata[label][meta_key] ||= formatted_name(base_name)
        else
          name, visit_ids = row
          grouped[formatted_name(name)].concat(Array(visit_ids))
        end
      end

      [ grouped, metadata ]
    end
  end
end
