# frozen_string_literal: true

require "digest"

class HomepagesController < InertiaController
  allow_unauthenticated_access
  disallow_account_scope
  before_action :skip_session_for_public_document
  after_action :clear_public_document_cookies

  CACHE_TTL = 5.minutes
  EDGE_CACHE_CONTROL = "public, max-age=#{CACHE_TTL.to_i}, stale-while-revalidate=60".freeze
  TABS = %w[popular recent trending].freeze

  def show
    tab = TABS.include?(params[:tab]) ? params[:tab] : "popular"
    return unless apply_public_cache_headers(tab:)

    cached = Rails.cache.fetch([ "public", "homepage", tab ], expires_in: CACHE_TTL) do
      {
        library_count: Library.count,
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
    def public_document_request?
      request.get? && request.format.html? && !request.inertia? && Current.identity.blank?
    end

    def skip_session_for_public_document
      return unless public_document_request?

      request.session_options[:skip] = true
    end

    def clear_public_document_cookies
      return unless public_document_request?

      response.delete_header("Set-Cookie")
    end

    def server_side_pageview_tracking_enabled_for_request?
      return false if public_document_request?

      super
    end

    def apply_public_cache_headers(tab:)
      if request.inertia?
        mark_non_cacheable!(private_cache: false)
        return true
      end

      if Current.identity.present?
        mark_non_cacheable!(private_cache: true)
        return true
      end

      expires_in CACHE_TTL, public: true
      response.set_header("Cloudflare-CDN-Cache-Control", EDGE_CACHE_CONTROL)

      stale?(
        etag: [
          "homepage",
          tab,
          Library.count,
          Library.maximum(:updated_at)&.utc&.to_i,
          homepage_library_signature(tab)
        ],
        last_modified: homepage_last_modified(tab),
        public: true
      )
    end

    def mark_non_cacheable!(private_cache:)
      response.delete_header("Cloudflare-CDN-Cache-Control")
      response.headers["Cache-Control"] = private_cache ? "private, no-store" : "no-store"
    end

    def homepage_last_modified(tab)
      timestamps = Library.public_send(tab).limit(10).pluck(:updated_at, :latest_version_at).flatten.compact
      timestamps << Library.maximum(:updated_at)
      timestamps.compact.max
    end

    def homepage_library_signature(tab)
      rows = Library.public_send(tab)
        .limit(10)
        .pluck(:id, :updated_at, :latest_version_at, :total_pages_count)

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
