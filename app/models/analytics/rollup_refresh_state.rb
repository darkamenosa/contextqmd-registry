# frozen_string_literal: true

class Analytics::RollupRefreshState < AnalyticsRecord
  self.table_name = "analytics_rollup_refresh_states"

  belongs_to :analytics_site, class_name: "Analytics::Site"

  class << self
    def cleanup_processed_before!(cutoff)
      where("request_version <= processed_version")
        .where("COALESCE(processed_at, updated_at) < ?", cutoff)
        .delete_all
    end
  end
end
