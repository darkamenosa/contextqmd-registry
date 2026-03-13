# frozen_string_literal: true

class BuildBundleJob < ApplicationJob
  queue_as :default

  def perform(bundle)
    bundle.build_now
  end
end
