# frozen_string_literal: true

module Analytics
  class ProfileSummaryRefreshJob < ApplicationJob
    queue_as :default

    discard_on ActiveJob::DeserializationError

    def perform(profile)
      profile.rebuild_summary_now
    end
  end
end
