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

    def screen_size_category_sql(column = "screen_size")
      <<~SQL.squish
        CASE
          WHEN #{column} IS NULL OR #{column} = '' THEN '(not set)'
          WHEN split_part(#{column}, 'x', 1) ~ '^[0-9]+$' THEN
            CASE
              WHEN CAST(split_part(#{column}, 'x', 1) AS integer) < 576 THEN 'Mobile'
              WHEN CAST(split_part(#{column}, 'x', 1) AS integer) < 992 THEN 'Tablet'
              WHEN CAST(split_part(#{column}, 'x', 1) AS integer) < 1440 THEN 'Laptop'
              ELSE 'Desktop'
            END
          ELSE #{column}
        END
      SQL
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

    def pluck_group_count_rows(scope, grouping)
      case grouping.fetch(:column)
      when :browser_version
        scope.group(Arel.sql("browser, browser_version"))
          .pluck(Arel.sql("browser, browser_version, COUNT(DISTINCT ahoy_visits.visitor_token)"))
      when :os_version
        scope.group(Arel.sql("os, os_version"))
          .pluck(Arel.sql("os, os_version, COUNT(DISTINCT ahoy_visits.visitor_token)"))
      when :os
        scope.group(Arel.sql("os"))
          .pluck(Arel.sql("os, COUNT(DISTINCT ahoy_visits.visitor_token)"))
      else
        scope.group(Arel.sql("browser"))
          .pluck(Arel.sql("browser, COUNT(DISTINCT ahoy_visits.visitor_token)"))
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
      duplicate_versions = duplicate_version_labels(rows, disambiguate_by_meta)

      rows.each do |row|
        if row.length == 3
          base_name, name, visit_ids = row
          display_name = display_name_for(base_name, name, duplicate_versions, disambiguate_by_meta)
          label = display_name
          grouped[label].concat(Array(visit_ids))
          store_group_metadata(metadata, label, base_name, display_name, meta_key)
        else
          name, visit_ids = row
          grouped[formatted_name(name)].concat(Array(visit_ids))
        end
      end

      [ grouped, metadata ]
    end

    def normalize_group_counts(rows, meta_key: nil, disambiguate_by_meta: false)
      counts = Hash.new(0)
      metadata = {}
      group_keys = Hash.new { |hash, key| hash[key] = [] }
      duplicate_versions = duplicate_version_labels(rows, disambiguate_by_meta)

      rows.each do |row|
        if row.length == 3
          base_name, name, visitors_count = row
          display_name = display_name_for(base_name, name, duplicate_versions, disambiguate_by_meta)
          counts[display_name] += visitors_count.to_i
          group_keys[display_name] |= [ { base_name: base_name, name: name } ]
          store_group_metadata(metadata, display_name, base_name, display_name, meta_key)
        else
          name, visitors_count = row
          label = formatted_name(name)
          counts[label] += visitors_count.to_i
          group_keys[label] |= [ { name: name } ]
        end
      end

      [ counts, metadata, group_keys ]
    end

    def grouped_visit_ids_for_names(scope, grouping, group_keys_by_name:, names:, meta_key: nil, disambiguate_by_meta: false)
      selected_keys = Array(names).flat_map { |name| Array(group_keys_by_name[name]) }.uniq
      return {} if selected_keys.empty?

      filtered_scope = filter_scope_for_group_keys(scope, grouping, selected_keys)
      grouped_visit_ids, = normalize_grouped_visit_ids(
        pluck_group_rows(filtered_scope, grouping),
        meta_key: meta_key,
        disambiguate_by_meta: disambiguate_by_meta
      )
      grouped_visit_ids
    end

    private
      def duplicate_version_labels(rows, disambiguate_by_meta)
        duplicate_versions = Hash.new { |hash, key| hash[key] = [] }
        return duplicate_versions unless disambiguate_by_meta

        rows.each do |row|
          next unless row.length == 3

          base_name, name, = row
          version_name = formatted_name(name)
          base_label = formatted_name(base_name)
          duplicate_versions[version_name] << base_label unless duplicate_versions[version_name].include?(base_label)
        end

        duplicate_versions
      end

      def display_name_for(base_name, name, duplicate_versions, disambiguate_by_meta)
        if disambiguate_by_meta &&
            duplicate_versions[formatted_name(name)].size > 1 &&
            base_name.present?
          formatted_name("#{base_name} #{name}")
        else
          formatted_name(name)
        end
      end

      def store_group_metadata(metadata, label, base_name, display_name, meta_key)
        return if base_name.blank? || meta_key.blank?

        metadata[label] ||= {}
        metadata[label][:display_name] ||= display_name
        metadata[label][meta_key] ||= formatted_name(base_name)
      end

      def filter_scope_for_group_keys(scope, grouping, group_keys)
        group_relations =
          group_keys.filter_map do |group_key|
            relation_for_group_key(scope, grouping, group_key)
          end

        if group_relations.any?
          group_relations.reduce(scope.none, &:or)
        else
          scope.none
        end
      end

      def relation_for_group_key(scope, grouping, group_key)
        case grouping.fetch(:column)
        when :browser_version
          scope.where(browser: group_key[:base_name], browser_version: group_key[:name])
        when :os_version
          scope.where(os: group_key[:base_name], os_version: group_key[:name])
        when :os
          scope.where(os: group_key[:name])
        else
          scope.where(browser: group_key[:name])
        end
      end
  end
end
