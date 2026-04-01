# frozen_string_literal: true

module Analytics::Properties
  RESERVED_KEYS = %w[page url title referrer screen_size engaged_ms scroll_depth].freeze

  class << self
    def filter_key?(key)
      key.to_s.start_with?("prop:")
    end

    def filter_name(key)
      key.to_s.delete_prefix("prop:").presence
    end

    def configured_keys(site = ::Analytics::Current.site_or_default)
      configured_typed_keys(site)
    end

    def available_keys(events = nil, site: ::Analytics::Current.site_or_default)
      configured = configured_keys(site)
      discovered =
        if events.present?
          event_keys(events)
        else
          discovered_keys(site:)
        end

      configured + (discovered - configured)
    end

    def available?(site: ::Analytics::Current.site_or_default)
      configured_keys(site).any? || discovered?(site:)
    end

    def managed_keys?(site: ::Analytics::Current.site_or_default)
      configured_typed_keys(site).any?
    end

    def event_keys(events)
      rows = Ahoy::Event.connection.select_values(<<~SQL.squish)
        SELECT DISTINCT key
        FROM (#{events.select("jsonb_object_keys(ahoy_events.properties) AS key").to_sql}) property_keys
      SQL

      rows
        .map(&:to_s)
        .reject(&:blank?)
        .reject { |key| RESERVED_KEYS.include?(key) }
        .sort
    end

    def discovered_keys(site: ::Analytics::Current.site_or_default)
      return [] unless site.present?
      return [] unless Ahoy::Event.table_exists?

      event_keys(discoverable_events_for_site(site))
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
      []
    end

    def discovered?(site: ::Analytics::Current.site_or_default)
      return false unless site.present?
      return false unless Ahoy::Event.table_exists?

      rows = Ahoy::Event.connection.select_values(<<~SQL.squish)
        SELECT DISTINCT key
        FROM (#{discoverable_events_for_site(site).select("jsonb_object_keys(ahoy_events.properties) AS key").to_sql}) property_keys
        LIMIT 20
      SQL

      rows.any? { |key| key.present? && !RESERVED_KEYS.include?(key.to_s) }
    rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
      false
    end

    def event_property_exists(property_name)
      Arel::Nodes::InfixOperation.new("?", properties_column, Arel::Nodes.build_quoted(property_name.to_s))
    end

    def event_property_value(property_name)
      value = Arel::Nodes::InfixOperation.new(
        "->>",
        properties_column,
        Arel::Nodes.build_quoted(property_name.to_s)
      )
      blank_to_null = Arel::Nodes::NamedFunction.new("NULLIF", [ value, Arel::Nodes.build_quoted("") ])
      Arel::Nodes::NamedFunction.new("COALESCE", [ blank_to_null, Arel::Nodes.build_quoted("(none)") ])
    end

    def event_property_value_lower(property_name)
      Arel::Nodes::NamedFunction.new("LOWER", [ event_property_value(property_name) ])
    end

    def apply_event_filters(events, filters)
      Array(filters).each do |entry|
        if entry.is_a?(Array) && entry.length == 3
          operator, key, value = entry
        else
          key, value = entry
          operator = "is"
        end
        next unless filter_key?(key)

        property_name = filter_name(key)
        next if property_name.blank? || value.to_s.strip.empty?

        value_expr = event_property_value(property_name)
        events = events.where(event_property_exists(property_name))
        case operator.to_s
        when "contains"
          events = events.where(event_property_value_lower(property_name).matches(Analytics::Search.contains_pattern(value)))
        when "is_not", "not_eq"
          events = events.where(value_expr.not_eq(value.to_s))
        when "is", "eq"
          events = events.where(value_expr.eq(value.to_s))
        else
          events = events.where(value_expr.eq(value.to_s))
        end
      end
      events
    end

    private
      def configured_typed_keys(site)
        return [] unless Analytics::AllowedEventProperty.table_exists?

        Analytics::AllowedEventProperty.configured_keys(site)
      rescue ActiveRecord::NoDatabaseError, ActiveRecord::StatementInvalid
        []
      end

      def discoverable_events_for_site(site)
        Ahoy::Event
          .for_analytics_site(site)
          .where.not(properties: [ nil, {} ])
      end

      def properties_column
        Ahoy::Event.arel_table[:properties]
      end
  end
end
