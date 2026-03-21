# frozen_string_literal: true

class CleanupWebsiteCrawlStateJob < ApplicationJob
  queue_as :background

  def perform
    WebsiteCrawl.cleanup_expired_staged_state_now
  end
end
