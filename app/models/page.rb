# frozen_string_literal: true

class Page < ApplicationRecord
  include PgSearch::Model

  belongs_to :version, counter_cache: true

  validates :page_uid, presence: true, uniqueness: { scope: :version_id }
  validates :path, presence: true
  validates :title, presence: true

  pg_search_scope :search_content,
    against: { title: "A", description: "B", path: "C" },
    using: {
      tsearch: {
        prefix: true,
        dictionary: "english",
        tsvector_column: "search_tsvector"
      }
    }

  scope :ordered, -> { order(path: :asc) }
end
