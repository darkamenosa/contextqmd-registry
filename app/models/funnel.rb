# frozen_string_literal: true

class Funnel < AnalyticsRecord
  self.table_name = "analytics_funnels"

  validates :name, presence: true, uniqueness: true
  validates :steps, presence: true

  def step_labels
    Array(steps).map do |s|
      next s.to_s unless s.is_a?(Hash)
      step = s.with_indifferent_access
      step[:name] || step[:value]
    end
  end
end
