# frozen_string_literal: true

class RankingsController < InertiaController
  allow_unauthenticated_access
  disallow_account_scope

  def index
    libraries = Library.includes(versions: :pages).all

    ranked = libraries.map { |lib| ranking_props(lib) }
      .sort_by { |r| -r[:score] }
      .each_with_index.map { |r, i| r.merge(rank: i + 1) }

    render inertia: "rankings/index", props: {
      libraries: ranked,
      total_libraries: libraries.size
    }
  end

  private

    def ranking_props(library)
      latest_version = library.versions.max_by(&:created_at)
      page_count = latest_version&.pages&.size || 0
      version_count = library.versions.size
      days_since_update = if latest_version&.created_at
        ((Time.current - latest_version.created_at) / 1.day).to_i
      else
        999
      end

      # Score: weighted combination of page count, version count, and freshness
      freshness = [ 1.0 - (days_since_update / 365.0), 0.0 ].max
      score = (page_count * 1.0) + (version_count * 5.0) + (freshness * 20.0)

      {
        namespace: library.namespace,
        name: library.name,
        display_name: library.display_name,
        page_count: page_count,
        version_count: version_count,
        freshness_pct: (freshness * 100).round,
        score: score.round(1),
        updated_at: (latest_version&.created_at || library.updated_at).iso8601
      }
    end
end
