# frozen_string_literal: true

class PagesController < InertiaController
  # Public marketing pages: allow guests and reject accidental /app/:account_id scoping.
  allow_unauthenticated_access
  disallow_account_scope

  def home
    libraries = Library.includes(:versions, :source_policy).order(:namespace, :name)

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
      latest_version = library.versions.max_by(&:created_at)
      {
        namespace: library.namespace,
        name: library.name,
        display_name: library.display_name,
        default_version: library.default_version,
        version_count: library.versions.size,
        page_count: latest_version&.pages&.count || 0,
        license_status: library.source_policy&.license_status,
        updated_at: (latest_version&.created_at || library.updated_at).iso8601
      }
    end
end
