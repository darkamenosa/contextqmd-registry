# frozen_string_literal: true

module Analytics::Goals
  class << self
    def available_names
      if managed_definitions?
        Goal.order(:display_name).pluck(:display_name)
      else
        legacy = AnalyticsSetting.get_json("goals", fallback: :missing)
        if legacy == :missing
          Ahoy::Event.where.not(name: [ "pageview", "engagement" ]).distinct.order(:name).pluck(:name)
        else
          Analytics::Lists.normalize_strings(legacy)
        end
      end
    end

    def available?
      if managed_definitions?
        Goal.exists?
      else
        legacy = AnalyticsSetting.get_json("goals", fallback: :missing)
        if legacy == :missing
          Ahoy::Event.where.not(name: [ "pageview", "engagement" ]).limit(1).exists?
        else
          Analytics::Lists.normalize_strings(legacy).any?
        end
      end
    end

    def configured(name)
      return unless managed_definitions?

      Goal.find_by(display_name: name.to_s)
    end

    def apply(events, goal)
      events =
        case goal.type
        when :event
          events.where(name: goal.event_name)
        when :page
          apply_page_goal(events, goal)
        when :scroll
          apply_scroll_goal(events, goal)
        else
          events
        end

      apply_custom_properties(events, goal.custom_props)
    end

    def managed_definitions?
      Goal.exists? || AnalyticsSetting.get_bool("goals_managed", fallback: false)
    end

    def apply_custom_properties(events, custom_props)
      Array(custom_props&.to_h).reduce(events) do |scope, (key, value)|
        property_name = key.to_s.strip
        property_value = value.to_s.strip
        next scope if property_name.blank? || property_value.blank?

        scope
          .where(Analytics::Properties.event_property_exists(property_name))
          .where(Analytics::Properties.event_property_value(property_name).eq(property_value))
      end
    end

    def wildcard_page_regex(page_path)
      if page_path.to_s.end_with?("*") && !page_path.to_s.end_with?("**") && page_path.to_s.count("*") == 1
        base = Regexp.escape(page_path.to_s.delete_suffix("*"))
        return "^#{base}(?:$|/.*)$"
      end

      escaped =
        page_path.to_s
          .yield_self { |value| Regexp.escape(value) }
          .gsub("\\*\\*", "__DOUBLE_WILDCARD__")
          .gsub("\\*", "[^/]*")
          .gsub("__DOUBLE_WILDCARD__", ".*")

      "^#{escaped}$"
    end
    private
      def page_match_node
        Arel.sql("COALESCE(NULLIF(split_part(ahoy_events.properties->>'page', CHR(63), 1), ''), '/')")
      end

      def page_matches(page_path)
        if page_path.to_s.include?("*")
          Arel::Nodes::InfixOperation.new(
            "~",
            page_match_node,
            Arel::Nodes.build_quoted(wildcard_page_regex(page_path))
          )
        else
          page_match_node.eq(page_path.to_s)
        end
      end

      def apply_page_goal(events, goal)
        scoped = events.where(name: "pageview")
        scoped.where(page_matches(goal.page_path))
      end

      def apply_scroll_goal(events, goal)
        scoped = events
          .where(name: "engagement")
          .where("COALESCE((ahoy_events.properties->>'scroll_depth')::float, 0) >= ?", goal.scroll_threshold.to_f)

        scoped.where(page_matches(goal.page_path))
      end
  end
end
