# frozen_string_literal: true

module Analytics
  class VisitSummaryRefreshJob < ApplicationJob
    queue_as :default

    discard_on ActiveJob::DeserializationError

    def perform(visit)
      Analytics::VisitSummary.refresh_visit!(visit)
    end
  end
end
