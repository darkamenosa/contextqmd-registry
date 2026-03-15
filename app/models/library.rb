# frozen_string_literal: true

class Library < ApplicationRecord
  include PgSearch::Model

  PATH_SAFE_SLUG = /\A[a-z0-9\-]+\z/

  belongs_to :account
  has_many :versions, dependent: :destroy
  has_many :library_sources, dependent: :destroy
  has_one :source_policy, dependent: :destroy

  before_validation :populate_slug

  validates :slug, presence: true,
    format: { with: PATH_SAFE_SLUG, message: "must be lowercase alphanumeric with hyphens" },
    uniqueness: true
  validates :namespace, presence: true,
    format: { with: PATH_SAFE_SLUG, message: "must be lowercase alphanumeric with hyphens" }
  validates :name, presence: true,
    format: { with: PATH_SAFE_SLUG, message: "must be a path-safe slug" }
  validates :display_name, presence: true
  validates :namespace, uniqueness: { scope: :name }

  pg_search_scope :search_by_query,
    against: %i[slug display_name],
    using: { tsearch: { prefix: true } }

  def to_param
    slug
  end

  # Resolve a query string to a library by alias match, then full-text search.
  def self.resolve(query)
    by_slug = find_by(slug: query)
    return by_slug if by_slug

    by_alias = where("aliases @> ?", [ query ].to_json)
    return by_alias.first if by_alias.exists?

    search_by_query(query).first
  end

  # Pick the version that gives users the best experience:
  # 1. The configured default_version if it has pages
  # 2. The version with the most pages (for crawled content)
  # 3. The first version
  def best_version(requested: nil)
    return nil if versions.empty?

    if requested.present?
      found = versions.find { |v| v.version == requested }
      return found if found
    end

    default_v = versions.find { |v| v.version == default_version }
    richest_v = versions.max_by { |v| v.pages.size }

    if default_v && default_v.pages.size > 0
      # Prefer richest if it has significantly more pages (3x threshold)
      if richest_v && richest_v.pages.size > default_v.pages.size * 3
        richest_v
      else
        default_v
      end
    else
      richest_v || versions.first
    end
  end

  private

    def populate_slug
      candidate = slug.presence || name
      self.slug = candidate.to_s.tr("_", "-").parameterize(separator: "-") if candidate.present?
    end
end
