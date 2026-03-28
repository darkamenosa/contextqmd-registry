# frozen_string_literal: true

class AnalyticsProfileSummary < AnalyticsRecord
  belongs_to :analytics_profile
  belongs_to :latest_visit, class_name: "Ahoy::Visit", foreign_key: :latest_visit_id, optional: true
end
