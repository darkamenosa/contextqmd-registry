# frozen_string_literal: true

class Page < ApplicationRecord
  belongs_to :version

  validates :page_uid, presence: true, uniqueness: { scope: :version_id }
  validates :path, presence: true
  validates :title, presence: true

  scope :ordered, -> { order(path: :asc) }
end
