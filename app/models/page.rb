# frozen_string_literal: true

class Page < ApplicationRecord
  include PgSearch::Model

  INDEXED_DESCRIPTION_LIMIT = 400_000
  # Keep this expression aligned with the capped GIN index in 20260317113000.
  CAPPED_DESCRIPTION_SQL = Arel.sql(%(left("pages"."description", #{INDEXED_DESCRIPTION_LIMIT})))

  belongs_to :version, counter_cache: true

  validates :page_uid, presence: true, uniqueness: { scope: :version_id }
  validates :path, presence: true
  validates :title, presence: true

  pg_search_scope :search_content,
    against: { title: "A", CAPPED_DESCRIPTION_SQL => "B", path: "C" },
    using: {
      tsearch: {
        prefix: true,
        dictionary: "english"
      }
    }

  scope :ordered, -> { order(path: :asc) }
end
