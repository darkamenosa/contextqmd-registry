# frozen_string_literal: true

module Analytics
  class SiteLocationHourlyVisitorRollupRefreshJob < ApplicationJob
    queue_as :default

    def perform(site_id, bucket_start)
      Analytics::SiteLocationHourlyVisitorRollup.perform_coalesced_refresh(site: site_id, bucket_start: bucket_start)
    end
  end
end
