# frozen_string_literal: true

class Analytics::Funnel < AnalyticsRecord
  self.table_name = "analytics_funnels"

  PAGE_MATCHES = %w[equals contains starts_with ends_with].freeze

  belongs_to :analytics_site, class_name: "Analytics::Site", optional: true

  before_validation :assign_current_site, on: :create

  validates :name, presence: true, uniqueness: { scope: :analytics_site_id }
  validates :steps, presence: true

  scope :global, -> { where(analytics_site_id: nil) }
  scope :for_analytics_site, ->(site = ::Analytics::Current.site_or_default) { Analytics::Scope.apply(all, site:) }

  class << self
    def effective_scope(site = ::Analytics::Current.site_or_default)
      site.present? ? for_analytics_site(site) : global
    end

    def effective_find_by_name(name, site = ::Analytics::Current.site_or_default)
      effective_scope(site).find_by(name: name.to_s)
    end

    def available?(site = ::Analytics::Current.site_or_default)
      effective_scope(site).exists?
    end

    def normalize_steps(steps)
      Array(steps).filter_map { |step| normalize_step(step) }
    end

    def normalize_step(step)
      case step
      when String
        normalize_legacy_string_step(step)
      when Hash
        normalize_hash_step(step)
      else
        nil
      end
    end

    private
      def normalize_legacy_string_step(step)
        value = step.to_s.strip
        return nil if value.blank?

        if value.start_with?("/")
          {
            "name" => value,
            "type" => "page_visit",
            "match" => "equals",
            "value" => value
          }
        else
          {
            "name" => value,
            "type" => "goal",
            "match" => "completes",
            "goal_key" => value
          }
        end
      end

      def normalize_hash_step(step)
        step = step.with_indifferent_access
        raw_type = step[:type].to_s
        type =
          case raw_type
          when "goal", "event"
            "goal"
          else
            "page_visit"
          end

        name = step[:name].presence || step[:label].presence

        if type == "goal"
          goal_key = step[:goal_key].presence || step[:goalKey].presence || step[:value].presence || name
          return nil if goal_key.blank?

          normalized = {
            "type" => "goal",
            "match" => "completes",
            "goal_key" => goal_key.to_s
          }
          normalized["name"] = name.to_s if name.present?
          normalized
        else
          value = step[:value].presence || name
          return nil if value.blank?

          match = step[:match].to_s
          match = "equals" unless PAGE_MATCHES.include?(match)

          normalized = {
            "type" => "page_visit",
            "match" => match,
            "value" => value.to_s
          }
          normalized["name"] = name.to_s if name.present?
          normalized
        end
      end
  end

  def step_labels
    normalized_steps.map { |step| step["name"].presence || step["goal_key"].presence || step["value"].to_s }
  end

  def normalized_steps
    self.class.normalize_steps(steps)
  end

  private
    def assign_current_site
      self.analytics_site ||= ::Analytics::Current.site_or_default
    end
end
