# frozen_string_literal: true

class HomepagesController < InertiaController
  allow_unauthenticated_access
  disallow_account_scope

  TABS = %w[popular recent trending].freeze

  def show
    tab = TABS.include?(params[:tab]) ? params[:tab] : "popular"

    render inertia: "pages/home", props: {
      library_count: Library.count,
      libraries: Library.public_send(tab).limit(10).map { |lib| home_library_props(lib) },
      active_tab: tab,
      seo: seo_props(
        title: "ContextQMD — Local-First Docs for AI",
        description: "Local-first documentation package system for CLI and MCP. Install, search, and retrieve version-aware docs for any library.",
        url: canonical_url(path: "/")
      ),
      json_ld: website_json_ld
    }
  end

  private

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
