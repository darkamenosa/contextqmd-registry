module Ahoy::Visit::Devices
  extend ActiveSupport::Concern

  class_methods do
    def devices_payload(query, limit: nil, page: nil, search: nil, order_by: nil)
      mode = query[:mode] || "browsers"
      filters = query[:filters] || {}
      range, = Ahoy::Visit.range_and_interval_for(query[:period], nil, query)
      visits = Ahoy::Visit.scoped_visits(range, filters)
      goal = filters["goal"].presence

      if mode == "screen-sizes"
        raw_grouped = visits.group(:screen_size).pluck(:screen_size, Arel.sql("ARRAY_AGG(id)"))
        categorized_visit_ids = Hash.new { |h, k| h[k] = [] }
        raw_grouped.each do |screen_size, visit_ids|
          category = categorize_screen_size(screen_size)
          categorized_visit_ids[category].concat(visit_ids)
        end
        counts = Ahoy::Visit.unique_counts_from_grouped_visit_ids(categorized_visit_ids, visits)
        items = counts.map { |name, n| { name: name.to_s.presence || UNKNOWN_LABEL, visitors: n } }
        if search.present?
          items = items.select { |it| it[:name].to_s.downcase.include?(search.downcase) }
        end

        if limit && page
          # Build counts from (possibly filtered) items
          items_counts = items.each_with_object({}) { |it, h| h[it[:name]] = it[:visitors].to_i }
          total = items_counts.values.sum.nonzero? || 1

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

          sorted_names = Ahoy::Visit.order_names(counts: items_counts, metrics_map: metrics_map, order_by: order_by)

          paged_names, has_more = Ahoy::Visit.paginate_names(sorted_names, limit: limit, page: page)
          grouped_page_visit_ids = categorized_visit_ids.slice(*paged_names)

          if goal.present?
            conversions, cr = Ahoy::Visit.conversions_and_rates(grouped_page_visit_ids, visits, range, filters, goal)
            page_items = paged_names.map { |name| { name: name, visitors: conversions[name] || 0, conversion_rate: cr[name] } }
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
          total = counts.values.sum.nonzero? || 1
          results = items.map { |it| it.merge(percentage: (it[:visitors].to_f / total).round(3)) }
          { results: results, metrics: %i[visitors percentage], meta: { has_more: false, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query) } }
        end
      else
        column = mode == "operating-systems" || mode == "operating-system-versions" ? :os : :browser
        expr = column.to_s
        pattern = search.present? ? Ahoy::Visit.like_contains(search) : nil

        if limit && page
          rel = visits
          rel = rel.where([ "LOWER(#{expr}) LIKE ?", pattern ]) if pattern.present?
          grouped_visit_ids = rel.group(Arel.sql(expr)).pluck(Arel.sql("#{expr}, ARRAY_AGG(ahoy_visits.id)")).to_h
          counts = Ahoy::Visit.unique_counts_from_grouped_visit_ids(grouped_visit_ids, visits)
          total = counts.values.sum.nonzero? || 1

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
          sorted_names = Ahoy::Visit.order_names(counts: counts, metrics_map: metrics_map, order_by: order_by)

          paged_names, has_more = Ahoy::Visit.paginate_names(sorted_names, limit: limit, page: page)
          page_visit_ids = grouped_visit_ids.slice(*paged_names)

          if goal.present?
            conversions, cr = Ahoy::Visit.conversions_and_rates(page_visit_ids, visits, range, filters, goal)
            results = paged_names.map { |name| { name: name.to_s.presence || UNKNOWN_LABEL, visitors: conversions[name] || 0, conversion_rate: cr[name] } }
            { results: results, metrics: %i[visitors conversion_rate], meta: { has_more: has_more, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query), metric_labels: { visitors: "Conversions", conversionRate: "Conversion Rate" } } }
          else
            results = paged_names.map do |name|
              n = counts[name]
              { name: name.to_s.presence || UNKNOWN_LABEL, visitors: n, percentage: (n.to_f / total).round(3) }
            end
            group_metrics = Ahoy::Visit.calculate_group_metrics(page_visit_ids, range, filters)
            paged_names.each_with_index do |name, i|
              results[i][:bounce_rate] = group_metrics.dig(name, :bounce_rate)
              results[i][:visit_duration] = group_metrics.dig(name, :visit_duration)
            end
            { results: results, metrics: %i[visitors percentage bounce_rate visit_duration], meta: { has_more: has_more, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query) } }
          end
        else
          grouped_visit_ids = visits.group(column).pluck(column, Arel.sql("ARRAY_AGG(id)")).to_h
          counts = Ahoy::Visit.unique_counts_from_grouped_visit_ids(grouped_visit_ids, visits)
          total = counts.values.sum.nonzero? || 1
          results = counts.map { |name, n| { name: name.to_s.presence || UNKNOWN_LABEL, visitors: n, percentage: (n.to_f / total).round(3) } }
          { results: results, metrics: %i[visitors percentage], meta: { has_more: false, skip_imported_reason: Ahoy::Visit.skip_imported_reason(query) } }
        end
      end
    end
    def categorize_screen_sizes(visits_scope)
      raw_counts = visits_scope.group(:screen_size).count
      categorized = Hash.new(0)

      raw_counts.each do |screen_size, count|
        category = categorize_screen_size(screen_size)
        categorized[category] += count
      end

      categorized
    end

    def categorize_screen_size(screen_size)
      return "(not set)" if screen_size.blank?

      if screen_size =~ /^(\d+)x(\d+)$/
        width = $1.to_i
        case width
        when 0...768 then "Mobile"
        when 768...1024 then "Tablet"
        when 1024...1440 then "Laptop"
        else "Desktop"
        end
      else
        screen_size
      end
    end
  end
end
