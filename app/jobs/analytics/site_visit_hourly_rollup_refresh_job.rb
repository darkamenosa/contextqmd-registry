# frozen_string_literal: true

module Analytics
  class SiteVisitHourlyRollupRefreshJob < ApplicationJob
    queue_as :default

    def perform(site_id, bucket_start)
      Analytics::SiteVisitHourlyRollup.perform_coalesced_refresh(site: site_id, bucket_start: bucket_start)
    end
  end
end
