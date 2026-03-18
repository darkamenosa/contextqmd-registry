# frozen_string_literal: true

class Library < ApplicationRecord
  include PgSearch::Model

  PATH_SAFE_SLUG = /\A[a-z0-9\-]+\z/
  SEARCH_VECTOR_SQL = <<~SQL.squish.freeze
    (
      setweight(to_tsvector('simple', coalesce(libraries.display_name, '')), 'A') ||
      setweight(to_tsvector('simple', coalesce(libraries.slug, '')), 'A') ||
      setweight(to_tsvector('simple', coalesce(libraries.name, '')), 'A') ||
      setweight(to_tsvector('simple', coalesce(libraries.namespace, '')), 'B') ||
      setweight(
        to_tsvector(
          'simple',
          coalesce(
            (
              SELECT string_agg(alias_term, ' ')
              FROM jsonb_array_elements_text(coalesce(libraries.aliases, '[]'::jsonb)) AS alias_term
            ),
            ''
          )
        ),
        'A'
      )
    )
  SQL

  belongs_to :account
  has_many :versions, dependent: :destroy
  has_many :library_sources, dependent: :destroy
  has_one :source_policy, dependent: :destroy

  scope :popular,  -> { order(total_pages_count: :desc, slug: :asc) }
  scope :recent,   -> { order(Arel.sql("latest_version_at DESC NULLS LAST"), :slug) }
  scope :trending, -> { where("total_pages_count > 0").order(Arel.sql("latest_version_at DESC NULLS LAST"), :slug) }
  scope :ranked,   -> { order(total_pages_count: :desc, versions_count: :desc, slug: :asc) }

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
    richest_v = versions.max_by(&:pages_count)

    if default_v && default_v.pages_count > 0
      # Prefer richest if it has significantly more pages (3x threshold)
      if richest_v && richest_v.pages_count > default_v.pages_count * 3
        richest_v
      else
        default_v
      end
    else
      richest_v || versions.first
    end
  end

  def primary_library_source
    library_sources.active.order(primary: :desc, updated_at: :desc).first
  end

  def enqueue_primary_source_check_if_due!(now: Time.current)
    source = primary_library_source
    return false unless source&.version_check_due?(now: now)

    source.enqueue_version_check!(now: now)
  end

  private

    def self.search_by_query(query)
      normalized = query.to_s.strip.downcase
      return none if normalized.blank?

      quoted_query = connection.quote(search_tsquery(normalized))
      quoted_alias_json = connection.quote([ normalized ].to_json)
      vector_sql = SEARCH_VECTOR_SQL
      alias_match_sql = <<~SQL.squish
        libraries.aliases @> #{quoted_alias_json}::jsonb
      SQL
      rank_sql = <<~SQL.squish
        (
          ts_rank(#{vector_sql}, to_tsquery('simple', #{quoted_query}), 0) +
          CASE WHEN lower(libraries.slug) = #{connection.quote(normalized)} THEN 4.0 ELSE 0.0 END +
          CASE WHEN lower(libraries.name) = #{connection.quote(normalized)} THEN 4.0 ELSE 0.0 END +
          CASE WHEN #{alias_match_sql} THEN 3.0 ELSE 0.0 END
        )
      SQL

      where("#{vector_sql} @@ to_tsquery('simple', #{quoted_query}) OR #{alias_match_sql}")
        .select(Arel.sql("libraries.*, #{rank_sql} AS search_rank"))
        .order(Arel.sql("#{rank_sql} DESC, libraries.slug ASC"))
    end

    def populate_slug
      candidate = slug.presence || name
      self.slug = candidate.to_s.tr("_", "-").parameterize(separator: "-") if candidate.present?
    end

    def self.search_tsquery(query)
      terms = query.scan(/[[:alnum:]]+/)
      return query if terms.empty?

      terms.map { |term| "#{term}:*" }.join(" & ")
    end
end
