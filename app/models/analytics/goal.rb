# frozen_string_literal: true

class Analytics::Goal < AnalyticsRecord
  self.table_name = "analytics_goals"

  MAX_CUSTOM_PROPS = 3

  belongs_to :analytics_site, class_name: "Analytics::Site", optional: true

  before_validation :assign_current_site, on: :create
  before_validation :normalize_fields
  before_validation :apply_default_display_name

  validates :display_name, presence: true, uniqueness: { scope: :analytics_site_id }
  validates :scroll_threshold, numericality: {
    greater_than_or_equal_to: -1,
    less_than_or_equal_to: 100
  }
  validate :validate_goal_shape
  validate :validate_custom_props

  scope :global, -> { where(analytics_site_id: nil) }
  scope :for_analytics_site, ->(site = ::Analytics::Current.site_or_default) { Analytics::Scope.apply(all, site:) }

  class << self
    def effective_scope(site = ::Analytics::Current.site_or_default)
      write_scope(site)
    end

    def write_scope(site = ::Analytics::Current.site_or_default)
      site.present? ? for_analytics_site(site) : global
    end

    def definition_payloads(site = ::Analytics::Current.site_or_default)
      effective_scope(site).order(:display_name).map(&:definition_payload)
    end

    def sync_from_definitions!(definitions, created_by_id: nil, site: ::Analytics::Current.site_or_default)
      payloads = Array(definitions).map do |definition|
        normalize_definition(definition)
      end

      transaction do
        relation = write_scope(site)
        keep_ids = payloads.map do |definition|
          goal = relation.find_or_initialize_by(display_name: definition.fetch(:display_name))
          goal.assign_attributes(definition.except(:display_name))
          goal.display_name = definition.fetch(:display_name)
          goal.analytics_site = site if site.present?
          goal.created_by_id ||= created_by_id
          goal.save!
          goal.id
        end

        scoped_relation = relation
        scoped_relation = scoped_relation.where.not(id: keep_ids) if keep_ids.any?
        scoped_relation.delete_all
      end
    end

    def effective_find_by_display_name(display_name, site = ::Analytics::Current.site_or_default)
      effective_scope(site).find_by(display_name: display_name.to_s)
    end

    def normalize_definition(definition)
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
    def assign_current_site
      self.analytics_site ||= ::Analytics::Current.site_or_default
    end

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
