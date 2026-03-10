# frozen_string_literal: true

class Bundle < ApplicationRecord
  belongs_to :version

  validates :profile, presence: true, uniqueness: { scope: :version_id }
  validates :format, presence: true
  validates :sha256, presence: true

  scope :ordered, -> { order(profile: :asc) }
end
