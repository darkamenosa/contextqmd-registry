# frozen_string_literal: true

class Analytics::Query
  SEMANTIC_KEYS = %i[
    dataset
    time_range
    filter_clauses
    order_by
    group_by
    measures
    options
    limit
    offset
  ].freeze
  FILTER_SOURCE_KEYS = %i[filters advanced_filters comparison_names comparison_codes].freeze
  TIME_RANGE_SOURCE_KEYS = %i[
    period
    date
    from
    to
    compare_from
    compare_to
    comparison
    match_day_of_week
    range_override
  ].freeze

  class << self
    def wrap(query)
      query.is_a?(self) ? query : new(query)
    end

    def from_ui_params(attributes = {}, dataset: nil, order_by: nil, limit: nil, page: nil)
      query = wrap(attributes)
      query = query.for_dataset(dataset) if dataset.present?
      query = query.with_order_by(order_by) if order_by.present?
      query = query.with_pagination(limit:, page:) if limit.present? || page.present?
      query
    end
  end

  def initialize(attributes = {})
    @attributes = normalize_hash(attributes)
    normalize_defaults!
    normalize_semantic_fields!
  end

  def [](key)
    attributes[key.to_sym]
  end

  def dig(*keys)
    attributes.dig(*keys.map { |key| key.is_a?(String) ? key.to_sym : key })
  end

  def fetch(key, *args, &block)
    attributes.fetch(key.to_sym, *args, &block)
  end

  def merge(other)
    updates = normalize_hash(other)
    merged_attributes = attributes.merge(updates)
    invalidate_derived_fields!(merged_attributes, updates)
    self.class.new(merged_attributes)
  end

  def compact
    self.class.new(attributes.compact)
  end

  def to_h
    attributes.deep_dup
  end

  def as_json(*)
    to_h
  end

  def ui_attributes
    to_h.except(*SEMANTIC_KEYS)
  end

  def dataset
    value = self[:dataset]
    value.present? ? value.to_sym : nil
  end

  def period
    self[:period] || time_range[:key]
  end

  def time_range
    self[:time_range] || {}.with_indifferent_access
  end

  def time_range_key
    time_range[:key].presence || self[:period]
  end

  def mode
    option(:mode)
  end

  def funnel
    option(:funnel)
  end

  def property
    option(:property)
  end

  def metric
    option(:metric)
  end

  def interval
    option(:interval)
  end

  def comparison
    self[:comparison].presence || time_range[:comparison]
  end

  def filter_clauses
    Array(self[:filter_clauses])
  end

  def order_by
    Array(self[:order_by])
  end

  def group_by
    Array(self[:group_by])
  end

  def measures
    Array(self[:measures])
  end

  def limit
    self[:limit]
  end

  def offset
    self[:offset].to_i
  end

  def options
    self[:options] || {}.with_indifferent_access
  end

  def option(key, default = nil)
    value = options[key]
    value.nil? ? default : value
  end

  def goal_filter_applied?
    filter_value(:goal).present?
  end

  def page_filter_applied?
    filter_value(:page).present? || filter_clauses.any? { |_operator, dimension, _value| dimension == :page }
  end

  def comparison_filter_names
    filter_clauses.filter_map do |operator, _dimension, value|
      next unless operator == :comparison_name

      normalized = value.to_s.strip
      normalized.presence
    end
  end

  def comparison_filter_codes
    filter_clauses.filter_map do |operator, _dimension, value|
      next unless operator == :comparison_code

      normalized = value.to_s.strip.upcase
      normalized.presence
    end
  end

  def with_imported?
    ActiveModel::Type::Boolean.new.cast(option(:with_imported))
  end

  def filters
    filter_clauses.each_with_object({}.with_indifferent_access) do |(operator, dimension, value), normalized|
      next unless operator == :eq

      normalized[dimension.to_s] = value
    end
  end

  def advanced_filters
    filter_clauses.filter_map do |operator, dimension, value|
      case operator
      when :not_eq
        [ "is_not", dimension.to_s, value ]
      when :contains
        [ "contains", dimension.to_s, value ]
      end
    end
  end

  def filter_value(dimension)
    clause = filter_clauses.find do |operator, current_dimension, _value|
      operator == :eq && current_dimension == dimension.to_sym
    end

    clause&.last
  end

  def filter_dimensions
    filter_clauses.filter_map do |operator, dimension, _value|
      next if operator.in?([ :comparison_name, :comparison_code ])

      dimension.to_s
    end.uniq
  end

  def without_goal
    without_filters_matching { |key| key.to_s == "goal" }
  end

  def without_goal_or_properties(property_filter: ->(_key) { false })
    without_filters_matching do |key|
      key.to_s == "goal" || property_filter.call(key)
    end
  end

  def for_dataset(dataset, **attributes)
    merge(attributes.merge(dataset:))
  end

  def with_order_by(order_by)
    merge(order_by:)
  end

  def with_options(updates)
    merge(options: options.to_h.merge(normalize_hash(updates)))
  end

  def with_option(key, value)
    with_options(key => value)
  end

  def with_filter(dimension, value)
    updated = filter_clauses.reject do |operator, current_dimension, _current_value|
      operator == :eq && current_dimension == dimension.to_sym
    end
    updated << [ :eq, dimension.to_sym, value ]
    merge(filter_clauses: updated)
  end

  def with_pagination(limit:, page:)
    normalized_limit = limit.present? ? limit.to_i : self.limit
    return self if normalized_limit.blank? || normalized_limit <= 0

    normalized_page = page.present? ? page.to_i : ((offset / normalized_limit) + 1)
    normalized_page = 1 if normalized_page <= 0

    merge(limit: normalized_limit, offset: [ normalized_page - 1, 0 ].max * normalized_limit)
  end

  private
    attr_reader :attributes

    def without_filters_matching(&matcher)
      rebuilt_attributes = to_h.deep_symbolize_keys.merge(
          filters: filters.to_h.reject { |key, _value| matcher.call(key) },
          advanced_filters: Array(advanced_filters).reject do |_op, dimension, _value|
            matcher.call(dimension)
          end
        )
      rebuilt_attributes.delete(:filter_clauses)

      self.class.new(rebuilt_attributes)
    end

    def normalize_defaults!
      @attributes[:filters] ||= {}.with_indifferent_access
      @attributes[:advanced_filters] ||= []
      @attributes[:labels] ||= {}.with_indifferent_access
      @attributes[:options] ||= nil
      @attributes[:group_by] ||= []
      @attributes[:measures] ||= []
    end

    def normalize_semantic_fields!
      @attributes[:dataset] = normalize_dataset(@attributes[:dataset]) if @attributes[:dataset].present?
      @attributes[:time_range] = normalize_time_range(@attributes[:time_range] || build_time_range)
      @attributes[:filter_clauses] = normalize_filter_clauses(@attributes[:filter_clauses] || build_filter_clauses)
      @attributes[:order_by] = normalize_order_by(@attributes[:order_by])
      raw_options = @attributes.key?(:options) ? @attributes[:options] : build_options
      @attributes[:options] = normalize_hash(raw_options || build_options).with_indifferent_access
      @attributes[:group_by] = normalize_names(@attributes[:group_by])
      @attributes[:measures] = normalize_names(@attributes[:measures])
      @attributes[:limit] = normalize_integer(@attributes[:limit]) if @attributes.key?(:limit)
      @attributes[:offset] = normalize_integer(@attributes[:offset]) || 0 if @attributes.key?(:offset)
    end

    def invalidate_derived_fields!(merged_attributes, updates)
      merged_attributes.delete(:time_range) if (updates.keys & TIME_RANGE_SOURCE_KEYS).any? && !updates.key?(:time_range)
      merged_attributes.delete(:filter_clauses) if (updates.keys & FILTER_SOURCE_KEYS).any? && !updates.key?(:filter_clauses)
    end

    def build_time_range
      {
        key: period,
        date: self[:date],
        from: self[:from],
        to: self[:to],
        compare_from: self[:compare_from],
        compare_to: self[:compare_to],
        comparison: comparison,
        match_day_of_week: self[:match_day_of_week],
        override: self[:range_override]
      }.compact
    end

    def build_filter_clauses
      clauses = raw_filters.to_h.map do |dimension, value|
        [ :eq, dimension.to_sym, value ]
      end

      clauses.concat(Array(raw_advanced_filters).filter_map do |operator, dimension, value|
        next if dimension.blank?

        [ normalize_operator(operator), dimension.to_sym, value ]
      end)

      clauses.concat(raw_comparison_names.map { |name| [ :comparison_name, :name, name ] })
      clauses.concat(raw_comparison_codes.map { |code| [ :comparison_code, :code, code ] })
      clauses
    end

    def build_options
      {
        mode: @attributes[:mode],
        funnel: @attributes[:funnel],
        property: @attributes[:property],
        metric: @attributes[:metric],
        interval: @attributes[:interval],
        dialog: @attributes[:dialog],
        with_imported: @attributes[:with_imported]
      }.compact
    end

    def normalize_time_range(value)
      normalize_hash(value).with_indifferent_access
    end

    def normalize_filter_clauses(value)
      Array(value).filter_map do |clause|
        next unless clause.is_a?(Array) && clause.length >= 3

        operator, dimension, clause_value = clause
        [ normalize_operator(operator), dimension.to_sym, clause_value ]
      end
    end

    def normalize_order_by(value)
      Array(value).filter_map do |entry|
        next unless entry.is_a?(Array) && entry.length >= 2

        field, direction = entry
        normalized_field = field.to_s.strip
        normalized_direction = direction.to_s.strip.downcase
        next if normalized_field.blank? || normalized_direction.blank?

        [ normalized_field.to_sym, normalized_direction.to_sym ]
      end
    end

    def normalize_names(value)
      Array(value).filter_map do |entry|
        normalized = entry.to_s.strip
        normalized.present? ? normalized.to_sym : nil
      end
    end

    def normalize_operator(value)
      case value.to_s
      when "is"
        :eq
      when "is_not"
        :not_eq
      when "contains"
        :contains
      else
        value.to_s.strip.presence&.to_sym
      end
    end

    def normalize_dataset(value)
      value.to_s.strip.presence&.to_sym
    end

    def normalize_integer(value)
      return nil if value.nil?

      integer = value.to_i
      integer.positive? ? integer : nil
    end

    def normalize_hash(value)
      case value
      when Analytics::Query
        value.to_h
      when Hash
        value.each_with_object({}) do |(key, item), normalized|
          normalized[key.to_sym] = normalize_value(item)
        end
      else
        {}
      end
    end

    def normalize_value(value)
      case value
      when Hash
        value.each_with_object({}.with_indifferent_access) do |(key, item), normalized|
          normalized[key] = normalize_value(item)
        end
      when Array
        value.map { |item| normalize_value(item) }
      else
        value
      end
    end

    def raw_filters
      @attributes[:filters] || {}
    end

    def raw_advanced_filters
      @attributes[:advanced_filters] || []
    end

    def raw_comparison_names
      Array(@attributes[:comparison_names]).filter_map do |name|
        normalized = name.to_s.strip
        normalized.presence
      end
    end

    def raw_comparison_codes
      Array(@attributes[:comparison_codes]).filter_map do |code|
        normalized = code.to_s.strip.upcase
        normalized.presence
      end
    end
end
