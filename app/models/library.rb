# frozen_string_literal: true

class Library < ApplicationRecord
  include PgSearch::Model

  PATH_SAFE_SLUG = /\A[a-z0-9\-]+\z/

  belongs_to :account
  has_many :versions, dependent: :destroy
  has_one :source_policy, dependent: :destroy

  validates :namespace, presence: true,
    format: { with: PATH_SAFE_SLUG, message: "must be lowercase alphanumeric with hyphens" }
  validates :name, presence: true,
    format: { with: PATH_SAFE_SLUG, message: "must be a path-safe slug" }
  validates :display_name, presence: true
  validates :namespace, uniqueness: { scope: :name }

  pg_search_scope :search_by_query,
    against: %i[namespace name display_name],
    using: { tsearch: { prefix: true } }
end
