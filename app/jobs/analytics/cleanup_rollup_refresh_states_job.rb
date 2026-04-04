# frozen_string_literal: true

module Analytics
  class CleanupRollupRefreshStatesJob < ApplicationJob
    queue_as :background

    RETENTION_PERIOD = 7.days

    def perform
      Analytics::RollupRefreshState.cleanup_processed_before!(RETENTION_PERIOD.ago)
    end
  end
end
