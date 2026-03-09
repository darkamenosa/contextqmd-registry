# frozen_string_literal: true

class SourcePolicy < ApplicationRecord
  belongs_to :library

  validates :license_status, inclusion: { in: %w[verified unclear custom] }

  def mirror_safe?
    license_status == "verified" && mirror_allowed?
  end
end
