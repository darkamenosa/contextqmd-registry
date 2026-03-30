# frozen_string_literal: true

class Analytics::Funnel < AnalyticsRecord
  self.table_name = "analytics_funnels"

  belongs_to :analytics_site, class_name: "Analytics::Site", optional: true

  before_validation :assign_current_site, on: :create

  validates :name, presence: true, uniqueness: { scope: :analytics_site_id }
  validates :steps, presence: true

  scope :global, -> { where(analytics_site_id: nil) }
  scope :for_analytics_site, ->(site = ::Analytics::Current.site_or_default) { Analytics::Scope.apply(all, site:) }

  class << self
    def effective_scope(site = ::Analytics::Current.site_or_default)
      site_scope = for_analytics_site(site)
      return site_scope if site.present? && site_scope.exists?

      global
    end

    def effective_find_by_name(name, site = ::Analytics::Current.site_or_default)
      effective_scope(site).find_by(name: name.to_s)
    end

    def available?(site = ::Analytics::Current.site_or_default)
      effective_scope(site).exists?
    end
  end

  def step_labels
    Array(steps).map do |s|
      next s.to_s unless s.is_a?(Hash)
      step = s.with_indifferent_access
      step[:name] || step[:value]
    end
  end

  private
    def assign_current_site
      self.analytics_site ||= ::Analytics::Current.site_or_default
    end
end
