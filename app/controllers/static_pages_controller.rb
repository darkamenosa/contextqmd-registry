# frozen_string_literal: true

class StaticPagesController < InertiaController
  # Public marketing/static pages: allow guests and reject accidental /app/:account_id scoping.
  allow_unauthenticated_access
  disallow_account_scope

  def home
    libraries = Library.includes(versions: :pages, source_policy: []).order(:namespace, :name)

    render inertia: "pages/home", props: {
      library_count: Library.count,
      version_count: Version.count,
      page_count: Page.count,
      libraries: libraries.map { |lib| home_library_props(lib) },
      crawl_pending: CrawlRequest.pending.count
    }
  end

  def about
    render inertia: "pages/about"
  end

  def privacy
    render inertia: "pages/privacy"
  end

  def terms
    render inertia: "pages/terms"
  end

  def contact
    render inertia: "pages/contact"
  end

  private

    def home_library_props(library)
      best_version = library.versions.max_by { |v| v.pages.size }
      latest_version = library.versions.max_by(&:created_at)
      {
        namespace: library.namespace,
        name: library.name,
        display_name: library.display_name,
        default_version: library.default_version,
        version: best_version&.version || latest_version&.version,
        version_count: library.versions.size,
        page_count: best_version&.pages&.size || 0,
        source_type: library.source_type,
        homepage_url: library.homepage_url,
        license_status: library.source_policy&.license_status,
        updated_at: (latest_version&.created_at || library.updated_at).iso8601
      }
    end
end
