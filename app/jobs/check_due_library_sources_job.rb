# frozen_string_literal: true

class CheckDueLibrarySourcesJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 500
  MAX_BATCHES = 10

  def perform(now = Time.current)
    MAX_BATCHES.times do
      sources = LibrarySource.version_check_due(now).order(:next_version_check_at).limit(BATCH_SIZE).to_a
      break if sources.empty?

      sources.each { |source| source.enqueue_version_check!(now: now) }
    end
  end
end
