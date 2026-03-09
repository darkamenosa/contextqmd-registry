# frozen_string_literal: true

require "active_support/concern"

module InertiaFlash
  extend ActiveSupport::Concern

  included do
    add_flash_types :success, :info, :warning

    inertia_share flash: -> { flash.to_hash }
  end
end
