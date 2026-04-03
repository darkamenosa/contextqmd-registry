# frozen_string_literal: true

module Analytics
  class VisitPageEngagementRefreshJob < ApplicationJob
    queue_as :default

    def perform(visit)
      Analytics::VisitPageEngagement.refresh_visit!(visit)
    end
  end
end
