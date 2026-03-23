# frozen_string_literal: true

class Page < ApplicationRecord
  include PgSearch::Model

  MAX_DESCRIPTION_LENGTH = 2_000_000

  belongs_to :version, counter_cache: true

  validates :page_uid, presence: true, uniqueness: { scope: :version_id }
  validates :path, presence: true
  validates :title, presence: true
  validates :description, length: { maximum: MAX_DESCRIPTION_LENGTH }

  pg_search_scope :search_content,
    against: { title: "A", description: "B", path: "C" },
    using: {
      tsearch: {
        prefix: true,
        dictionary: "english"
      }
    }

  scope :ordered, -> { order(path: :asc) }
end
