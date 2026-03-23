# frozen_string_literal: true

class RankingsController < InertiaController
  include Pagy::Method

  CACHE_TTL = 5.minutes

  allow_unauthenticated_access
  disallow_account_scope

  def index
    page = params[:page].presence || "1"
    cached = Rails.cache.fetch([ "public", "rankings", page ], expires_in: CACHE_TTL) do
      pagy, paginated = pagy(:offset, Library.ranked, limit: 10)

      {
        libraries: paginated.map.with_index { |lib, i| ranking_props(lib, rank: pagy.offset + i + 1) },
        pagination: pagination_props(pagy),
        total_libraries: Library.count
      }
    end

    render inertia: "rankings/index", props: {
      libraries: cached[:libraries],
      pagination: cached[:pagination],
      total_libraries: cached[:total_libraries],
      seo: seo_props(
        title: "Rankings",
        description: "Documentation coverage rankings for libraries on ContextQMD. Sorted by page count, versions, and freshness.",
        url: canonical_url(allowed_params: [ :page ])
      )
    }
  end

  private

    def ranking_props(library, rank:)
      days_since_update = library.latest_version_at ? ((Time.current - library.latest_version_at) / 1.day).to_i : 999
      freshness = [ 1.0 - (days_since_update / 365.0), 0.0 ].max

      {
        slug: library.slug,
        display_name: library.display_name,
        homepage_url: library.homepage_url,
        source_type: library.source_type,
        page_count: library.total_pages_count,
        version_count: library.versions_count,
        freshness_pct: (freshness * 100).round,
        updated_at: (library.latest_version_at || library.updated_at).iso8601,
        rank: rank
      }
    end
end
