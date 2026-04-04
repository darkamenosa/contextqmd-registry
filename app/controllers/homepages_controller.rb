# frozen_string_literal: true

class HomepagesController < InertiaController
  allow_unauthenticated_access
  disallow_account_scope

  CACHE_TTL = 5.minutes
  TABS = %w[popular recent trending].freeze

  def show
    tab = TABS.include?(params[:tab]) ? params[:tab] : "popular"
    library_count = Library.count
    last_modified = [ Library.maximum(:updated_at), Library.maximum(:latest_version_at) ].compact.max
    visible_signature = homepage_library_signature(tab)

    merge_vary_header!("X-Inertia")

    if flash.to_hash.present?
      response.headers["Cache-Control"] = "no-store"
    else
      fresh_when(
        etag: [
          request.inertia? ? "inertia" : "html",
          "homepage",
          tab,
          *shared_identity_cache_key_parts,
          library_count,
          visible_signature,
          last_modified&.to_fs(:usec)
        ],
        last_modified: last_modified,
        public: false,
        template: false
      )
      return if performed?
    end

    cached = Rails.cache.fetch([ "public", "homepage", tab, library_count, last_modified&.to_fs(:usec) ], expires_in: CACHE_TTL) do
      {
        library_count: library_count,
        libraries: Library.public_send(tab).limit(10).map { |lib| home_library_props(lib) },
        active_tab: tab
      }
    end

    render inertia: "pages/home", props: {
      library_count: cached[:library_count],
      libraries: cached[:libraries],
      active_tab: cached[:active_tab],
      seo: seo_props(
        title: "ContextQMD — Local-First Docs for AI",
        description: "Local-first documentation package system for CLI and MCP. Install, search, and retrieve version-aware docs for any library.",
        url: canonical_url(path: "/")
      ),
      json_ld: website_json_ld
    }
  end

  private

    def homepage_library_signature(tab)
      rows = Library.public_send(tab)
        .limit(10)
        .pluck(
          :id,
          :slug,
          :display_name,
          :homepage_url,
          :source_type,
          :total_pages_count,
          :updated_at,
          :latest_version_at
        )

      Digest::SHA256.hexdigest(rows.to_json)
    end

    def website_json_ld
      {
        "@context": "https://schema.org",
        "@type": "WebSite",
        name: "ContextQMD",
        url: "https://#{canonical_host}/"
      }
    end

    def home_library_props(library)
      {
        slug: library.slug,
        display_name: library.display_name,
        page_count: library.total_pages_count,
        source_type: library.source_type,
        homepage_url: library.homepage_url,
        updated_at: (library.latest_version_at || library.updated_at).iso8601
      }
    end
end
