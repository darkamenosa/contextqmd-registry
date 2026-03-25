module Ahoy::Visit::Devices
  extend ActiveSupport::Concern

  class_methods do
    def devices_payload(query, limit: nil, page: nil, search: nil, order_by: nil)
      mode = query[:mode] || "browsers"
      filters = query[:filters] || {}
      advanced_filters = query[:advanced_filters] || []
      comparison_names = Ahoy::Visit.comparison_names_filter(query)
      range, = Ahoy::Visit.range_and_interval_for(query[:period], nil, query)
      visits = Ahoy::Visit.scoped_visits(range, filters, advanced_filters: advanced_filters)
      goal = filters["goal"].presence

      if mode == "screen-sizes"
        raw_grouped = visits.group(:screen_size).pluck(:screen_size, Arel.sql("ARRAY_AGG(id)"))
        categorized_visit_ids = Hash.new { |h, k| h[k] = [] }
        raw_grouped.each do |screen_size, visit_ids|
          category = categorize_screen_size(screen_size)
          categorized_visit_ids[category].concat(visit_ids)
        end
        counts = Ahoy::Visit.unique_counts_from_grouped_visit_ids(categorized_visit_ids, visits)
        items = counts.map { |name, n| { name: name.to_s.presence || Ahoy::Visit::Constants::UNKNOWN_LABEL, visitors: n } }
        if search.present?
          items = items.select { |it| it[:name].to_s.downcase.include?(search.downcase) }
        end
        if comparison_names.any?
          items = items.select { |it| comparison_names.include?(it[:name].to_s) }
          categorized_visit_ids.select! { |name, _| comparison_names.include?(name.to_s) }
        end

        if limit && page
          # Build counts from (possibly filtered) items
          items_counts = items.each_with_object({}) { |it, h| h[it[:name]] = it[:visitors].to_i }
          total = Ahoy::Visit.percentage_total_visitors(visits)
          denominator_counts = goal.present? ? goal_denominator_counts_for_devices(query, mode: mode, search: search) : nil

          sorted_names =
            if goal.present?
              conversions_all, cr_all = Ahoy::Visit.conversions_and_rates(categorized_visit_ids, visits, range, filters, goal, advanced_filters: advanced_filters, denominator_counts: denominator_counts)
              Ahoy::Visit.order_names_with_conversions(conversions: conversions_all, cr: cr_all, order_by: order_by)
            else
              metrics_map = {}
              if order_by
                metric, _ = order_by
                if metric == "percentage"
                  metrics_map = items_counts.keys.index_with { |n| { percentage: (items_counts[n].to_f / total) } }
                elsif %w[bounce_rate visit_duration].include?(metric)
                  metrics_all = Ahoy::Visit.calculate_group_metrics(categorized_visit_ids, range, filters)
                  metrics_map = items_counts.keys.index_with { |n| metrics_all[n] || {} }
                end
              end

              Ahoy::Visit.order_names(counts: items_counts, metrics_map: metrics_map, order_by: order_by)
            end

          paged_names, has_more = Ahoy::Visit.paginate_names(sorted_names, limit: limit, page: page)
          grouped_page_visit_ids = categorized_visit_ids.slice(*paged_names)

          if goal.present?
            conversions, cr = Ahoy::Visit.conversions_and_rates(grouped_page_visit_ids, visits, range, filters, goal, advanced_filters: advanced_filters, denominator_counts: denominator_counts)
            page_items = paged_names.map do |name|
              label = name.to_s
              { name: label, visitors: conversions[name] || 0, conversion_rate: Ahoy::Visit.goal_conversion_rate(conversions[name] || 0, denominator_counts[label]) }
            end
            { results: page_items, metrics: %i[visitors conversion_rate], meta: { has_more: has_more, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query), metric_labels: { visitors: "Conversions", conversionRate: "Conversion Rate" } } }
          else
            page_items = paged_names.map do |name|
              v = items_counts[name]
              { name: name, visitors: v, percentage: (v.to_f / total).round(3) }
            end
            group_metrics = Ahoy::Visit.calculate_group_metrics(grouped_page_visit_ids, range, filters)
            page_items.each { |it| it[:bounce_rate] = group_metrics.dig(it[:name], :bounce_rate); it[:visit_duration] = group_metrics.dig(it[:name], :visit_duration) }
            { results: page_items, metrics: %i[visitors percentage bounce_rate visit_duration], meta: { has_more: has_more, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query) } }
          end
        else
          total = Ahoy::Visit.percentage_total_visitors(visits)
          results = items.map { |it| it.merge(percentage: (it[:visitors].to_f / total).round(3)) }
          { results: results, metrics: %i[visitors percentage], meta: { has_more: false, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query) } }
        end
      else
        grouping = device_grouping_for_mode(mode)
        column = grouping.fetch(:column)
        base_column = grouping[:base_column]
        pattern = search.present? ? Ahoy::Visit.like_contains(search) : nil

        if limit && page
          rel = visits
          rel = apply_device_search(rel, grouping, pattern) if pattern.present?
          grouped_visit_ids, group_metadata = normalize_device_grouped_visit_ids(
            pluck_device_group_rows(rel, grouping),
            meta_key: grouping[:meta_key],
            disambiguate_by_meta: disambiguate_device_versions?(grouping, filters)
          )
          counts = Ahoy::Visit.unique_counts_from_grouped_visit_ids(grouped_visit_ids, visits)
          if comparison_names.any?
            grouped_visit_ids.select! do |name, _|
              comparison_names.include?(formatted_device_name(name))
            end
            counts.select! do |name, _|
              comparison_names.include?(formatted_device_name(name))
            end
            group_metadata.select! do |name, _|
              comparison_names.include?(formatted_device_name(name))
            end
          end
          total = Ahoy::Visit.percentage_total_visitors(visits)
          denominator_counts = goal.present? ? goal_denominator_counts_for_devices(query, mode: mode, search: search) : nil

          sorted_names =
            if goal.present?
              conversions_all, cr_all = Ahoy::Visit.conversions_and_rates(grouped_visit_ids, visits, range, filters, goal, advanced_filters: advanced_filters, denominator_counts: denominator_counts)
              Ahoy::Visit.order_names_with_conversions(conversions: conversions_all, cr: cr_all, order_by: order_by)
            else
              metrics_map = {}
              if order_by
                metric, _ = order_by
                if metric == "percentage"
                  metrics_map = counts.keys.index_with { |n| { percentage: (counts[n].to_f / total) } }
                elsif %w[bounce_rate visit_duration].include?(metric)
                  metrics_all = Ahoy::Visit.calculate_group_metrics(grouped_visit_ids, range, filters)
                  metrics_map = counts.keys.index_with { |n| metrics_all[n] || {} }
                end
              end

              Ahoy::Visit.order_names(counts: counts, metrics_map: metrics_map, order_by: order_by)
            end

          paged_names, has_more = Ahoy::Visit.paginate_names(sorted_names, limit: limit, page: page)
          page_visit_ids = grouped_visit_ids.slice(*paged_names)

          if goal.present?
            conversions, cr = Ahoy::Visit.conversions_and_rates(page_visit_ids, visits, range, filters, goal, advanced_filters: advanced_filters, denominator_counts: denominator_counts)
            results = paged_names.map do |name|
              label = name.to_s.presence || Ahoy::Visit::Constants::UNKNOWN_LABEL
              build_device_result(
                name: label,
                group_metadata: group_metadata,
                metrics: {
                  visitors: conversions[name] || 0,
                  conversion_rate: Ahoy::Visit.goal_conversion_rate(conversions[name] || 0, denominator_counts[label])
                }
              )
            end
            { results: results, metrics: %i[visitors conversion_rate], meta: { has_more: has_more, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query), metric_labels: { visitors: "Conversions", conversionRate: "Conversion Rate" } } }
          else
            results = paged_names.map do |name|
              n = counts[name]
              build_device_result(
                name: name.to_s.presence || Ahoy::Visit::Constants::UNKNOWN_LABEL,
                group_metadata: group_metadata,
                metrics: {
                  visitors: n,
                  percentage: (n.to_f / total).round(3)
                }
              )
            end
            group_metrics = Ahoy::Visit.calculate_group_metrics(page_visit_ids, range, filters)
            paged_names.each_with_index do |name, i|
              results[i][:bounce_rate] = group_metrics.dig(name, :bounce_rate)
              results[i][:visit_duration] = group_metrics.dig(name, :visit_duration)
            end
            { results: results, metrics: %i[visitors percentage bounce_rate visit_duration], meta: { has_more: has_more, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query) } }
          end
        else
          grouped_visit_ids, group_metadata = normalize_device_grouped_visit_ids(
            pluck_device_group_rows(visits, grouping),
            meta_key: grouping[:meta_key],
            disambiguate_by_meta: disambiguate_device_versions?(grouping, filters)
          )
          counts = Ahoy::Visit.unique_counts_from_grouped_visit_ids(grouped_visit_ids, visits)
          total = Ahoy::Visit.percentage_total_visitors(visits)
          results = counts.map do |name, n|
            build_device_result(
              name: name.to_s.presence || Ahoy::Visit::Constants::UNKNOWN_LABEL,
              group_metadata: group_metadata,
              metrics: {
                visitors: n,
                percentage: (n.to_f / total).round(3)
              }
            )
          end
          { results: results, metrics: %i[visitors percentage], meta: { has_more: false, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query) } }
        end
      end
    end
    def categorize_screen_size(screen_size)
      return "(not set)" if screen_size.blank?

      if screen_size =~ /^(\d+)x(\d+)$/
        width = $1.to_i
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

    def goal_denominator_counts_for_devices(query, mode:, search: nil)
      base_query = Ahoy::Visit.query_without_goal_and_props(query).merge(mode: mode)
      payload = devices_payload(base_query, search: search)
      payload.fetch(:results, []).each_with_object({}) do |row, counts|
        counts[row[:name].to_s] = row[:visitors].to_i
      end
    end

    def formatted_device_name(name)
      name.to_s.presence || Ahoy::Visit::Constants::UNKNOWN_LABEL
    end

    def device_grouping_for_mode(mode)
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

    def apply_device_search(scope, grouping, pattern)
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

    def pluck_device_group_rows(scope, grouping)
      case grouping.fetch(:column)
      when :browser_version
        scope
          .group(Arel.sql("browser, browser_version"))
          .pluck(Arel.sql("browser, browser_version, ARRAY_AGG(ahoy_visits.id)"))
      when :os_version
        scope
          .group(Arel.sql("os, os_version"))
          .pluck(Arel.sql("os, os_version, ARRAY_AGG(ahoy_visits.id)"))
      when :os
        scope
          .group(Arel.sql("os"))
          .pluck(Arel.sql("os, ARRAY_AGG(ahoy_visits.id)"))
      else
        scope
          .group(Arel.sql("browser"))
          .pluck(Arel.sql("browser, ARRAY_AGG(ahoy_visits.id)"))
      end
    end

    def build_device_result(name:, group_metadata:, metrics:)
      metadata = group_metadata[name] || {}
      metadata.merge(name: metadata[:display_name] || name).merge(metrics)
    end

    def disambiguate_device_versions?(grouping, filters)
      case grouping.fetch(:column)
      when :browser_version
        filters["browser"].blank?
      when :os_version
        filters["os"].blank?
      else
        false
      end
    end

    def normalize_device_grouped_visit_ids(rows, meta_key: nil, disambiguate_by_meta: false)
      grouped = Hash.new { |hash, key| hash[key] = [] }
      metadata = {}
      duplicate_versions = Hash.new { |hash, key| hash[key] = [] }

      if disambiguate_by_meta
        rows.each do |row|
          next unless row.length == 3

          base_name, name, = row
          version_name = formatted_device_name(name)
          base_label = formatted_device_name(base_name)
          duplicate_versions[version_name] << base_label unless duplicate_versions[version_name].include?(base_label)
        end
      end

      rows.each do |row|
        if row.length == 3
          base_name, name, visit_ids = row
          display_name =
            if disambiguate_by_meta &&
                duplicate_versions[formatted_device_name(name)].size > 1 &&
                base_name.present?
              formatted_device_name("#{base_name} #{name}")
            else
              formatted_device_name(name)
            end

          label = display_name
          grouped[label].concat(Array(visit_ids))
          next if base_name.blank? || meta_key.blank?

          metadata[label] ||= {}
          metadata[label][:display_name] ||= display_name
          metadata[label][meta_key] ||= formatted_device_name(base_name)
        else
          name, visit_ids = row
          grouped[formatted_device_name(name)].concat(Array(visit_ids))
        end
      end

      [ grouped, metadata ]
    end
  end
end
