# frozen_string_literal: true

class Goal < AnalyticsRecord
  self.table_name = "analytics_goals"

  MAX_CUSTOM_PROPS = 3

  before_validation :normalize_fields
  before_validation :apply_default_display_name

  validates :display_name, presence: true, uniqueness: true
  validates :scroll_threshold, numericality: {
    greater_than_or_equal_to: -1,
    less_than_or_equal_to: 100
  }
  validate :validate_goal_shape
  validate :validate_custom_props

  def self.definition_payloads
    order(:display_name).map(&:definition_payload)
  end

  def self.sync_from_definitions!(definitions, created_by_id: nil)
    payloads = Array(definitions).map do |definition|
      normalize_definition(definition)
    end

    transaction do
      keep_ids = payloads.map do |definition|
        goal = find_or_initialize_by(display_name: definition.fetch(:display_name))
        goal.assign_attributes(definition.except(:display_name))
        goal.display_name = definition.fetch(:display_name)
        goal.created_by_id ||= created_by_id
        goal.save!
        goal.id
      end

      relation = all
      relation = relation.where.not(id: keep_ids) if keep_ids.any?
      relation.delete_all
    end
  end

  def self.normalize_definition(definition)
    attrs = definition.respond_to?(:to_h) ? definition.to_h : {}
    attrs = attrs.deep_symbolize_keys

    custom_props =
      attrs[:custom_props].is_a?(Hash) ? attrs[:custom_props] : {}

    {
      display_name: attrs[:display_name].to_s.strip,
      event_name: attrs[:event_name].to_s.strip.presence,
      page_path: attrs[:page_path].to_s.strip.presence,
      scroll_threshold: attrs.key?(:scroll_threshold) ? attrs[:scroll_threshold].to_i : -1,
      custom_props: custom_props.transform_keys(&:to_s).transform_values(&:to_s)
    }
  end

  def type
    if event_name.present?
      :event
    elsif scroll_threshold.to_i >= 0
      :scroll
    else
      :page
    end
  end

  def definition_payload
    {
      display_name: display_name,
      event_name: event_name,
      page_path: page_path,
      scroll_threshold: scroll_threshold,
      custom_props: custom_props || {}
    }
  end

  private
    def normalize_fields
      self.display_name = display_name.to_s.strip.presence
      self.event_name = event_name.to_s.strip.presence
      self.page_path = page_path.to_s.strip.presence
      self.page_path = "/#{page_path}" if page_path.present? && !page_path.start_with?("/")
      self.scroll_threshold = scroll_threshold.to_i if scroll_threshold.present?
      self.custom_props =
        (custom_props.is_a?(Hash) ? custom_props : {})
          .transform_keys { |key| key.to_s.strip }
          .transform_values { |value| value.to_s.strip }
          .reject { |key, value| key.blank? || value.blank? }
    end

    def apply_default_display_name
      self.display_name ||= if event_name.present?
        event_name
      elsif page_path.present?
        scroll_threshold.to_i >= 0 ? "Scroll #{page_path}" : "Visit #{page_path}"
      end
    end

    def validate_goal_shape
      if event_name.present? && page_path.present?
        errors.add(:base, "event_name and page_path cannot both be set")
      elsif event_name.blank? && page_path.blank?
        errors.add(:base, "event_name or page_path must be set")
      end

      if event_name.present? && scroll_threshold.to_i >= 0
        errors.add(:scroll_threshold, "must be -1 for event goals")
      end

      if page_path.blank? && scroll_threshold.to_i >= 0
        errors.add(:page_path, "must be set for scroll goals")
      end
    end

    def validate_custom_props
      unless custom_props.is_a?(Hash)
        errors.add(:custom_props, "must be a map")
        return
      end

      if custom_props.size > MAX_CUSTOM_PROPS
        errors.add(:custom_props, "use at most #{MAX_CUSTOM_PROPS} properties per goal")
      end
    end
end
