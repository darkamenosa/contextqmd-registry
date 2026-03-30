# frozen_string_literal: true

class AnalyticsProfileSummary < AnalyticsRecord
  belongs_to :analytics_profile
  belongs_to :latest_visit, class_name: "Ahoy::Visit", foreign_key: :latest_visit_id, optional: true
  belongs_to :analytics_site, class_name: "Analytics::Site", optional: true

  scope :for_analytics_site, ->(site = ::Analytics::Current.site) { Analytics::Scope.apply(all, site:) }
end
