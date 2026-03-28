# frozen_string_literal: true

module Analytics
  class ProfileProjectionJob < ApplicationJob
    queue_as :default

    discard_on ActiveJob::DeserializationError

    def perform(profile)
      profile.rebuild_projection_now
    end
  end
end
