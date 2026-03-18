# frozen_string_literal: true

class CheckLibrarySourceJob < ApplicationJob
  discard_on ActiveJob::DeserializationError

  queue_as :default

  retry_on DocsFetcher::TransientFetchError, attempts: 3, wait: :polynomially_longer

  def perform(source)
    source.check_for_new_version!
  end
end
