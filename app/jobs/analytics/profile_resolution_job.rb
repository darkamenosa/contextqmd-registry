# frozen_string_literal: true

module Analytics
  class ProfileResolutionJob < ApplicationJob
    queue_as :default

    discard_on ActiveJob::DeserializationError

    def perform(visit, browser_id:, strong_keys:, occurred_at: nil)
      visit.resolve_profile_now(
        browser_id: browser_id,
        strong_keys: strong_keys,
        occurred_at: occurred_at
      )
    end
  end
end
