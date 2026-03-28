# frozen_string_literal: true

module Analytics
  class VisitProjectionJob < ApplicationJob
    queue_as :default

    discard_on ActiveJob::DeserializationError

    def perform(visit, previous_profile_id: nil)
      visit.project_now(previous_profile_id: previous_profile_id)
    end
  end
end
