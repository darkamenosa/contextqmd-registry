# frozen_string_literal: true

class Analytics::SiteTrackingRule < AnalyticsRecord
  self.table_name = "analytics_site_tracking_rules"

  belongs_to :analytics_site, class_name: "Analytics::Site"

  validates :analytics_site, presence: true, uniqueness: true

  before_validation :normalize_fields

  private
    def normalize_fields
      self.include_paths = normalize_path_list(include_paths)
      self.exclude_paths = normalize_path_list(exclude_paths)
    end

    def normalize_path_list(values)
      Array(values).each_with_object([]) do |value, list|
        normalized = value.to_s.strip
        next if normalized.blank?
        next if list.include?(normalized)

        list << normalized
      end
    end
end
