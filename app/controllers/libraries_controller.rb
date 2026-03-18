# frozen_string_literal: true

class LibrariesController < InertiaController
  include Pagy::Method

  allow_unauthenticated_access
  disallow_account_scope
  before_action :authenticate_identity!, only: [ :new, :create ]

  def index
    libraries = if params[:query].present?
      search_libraries(params[:query]).includes(:source_policy, :versions)
    else
      Library.all.includes(:source_policy, :versions).order(:slug)
    end

    pagy, paginated = pagy(:offset, libraries, limit: 10)

    render inertia: "libraries/index", props: {
      libraries: paginated.map { |lib| library_props(lib) },
      pagination: pagination_props(pagy),
      query: params[:query] || "",
      seo: seo_props(
        title: "Libraries",
        description: "Browse version-aware documentation packages for libraries. Search, install, and use with CLI or MCP.",
        url: canonical_url(allowed_params: [ :page ]),
        noindex: params[:query].present? ? true : nil
      )
    }
  end

  def show
    library = Library.includes(:versions, :source_policy, :library_sources).find_by!(slug: params[:slug])
    library.enqueue_primary_source_check_if_due!
    versions = library.versions.ordered

    selected_version = library.best_version(requested: params[:version])
    search_query = params[:search].to_s.strip
    search_active = search_query.present?

    # Paginate pages for the selected version
    pages_scope = selected_version ? selected_version.pages : Page.none
    pages_scope = if search_active
      pages_scope.search_content(search_query)
    else
      pages_scope.order(:path)
    end
    pagy, pages = if search_active
      pagy(:countless, pages_scope, limit: 30)
    else
      pagy(:offset, pages_scope, limit: 30)
    end

    render inertia: "libraries/show", props: {
      library: library_props(library),
      versions: versions.map { |v| version_props(v) },
      pages: pages.map { |p| page_props(p) },
      selected_version: selected_version&.version,
      pagination: pagination_props(pagy),
      search: search_query,
      search_active: search_active,
      seo: seo_props(
        title: "#{library.display_name} Documentation",
        description: library_meta_description(library),
        url: canonical_url(path: "/libraries/#{library.slug}", allowed_params: [ :page ]),
        noindex: search_active ? true : nil
      ),
      json_ld: breadcrumb_json_ld([
        { name: "Libraries", url: "https://#{canonical_host}/libraries" },
        { name: library.display_name, url: "https://#{canonical_host}/libraries/#{library.slug}" }
      ])
    }
  rescue ActiveRecord::RecordNotFound
    redirect_to libraries_path, alert: "Library not found"
  end

  def new
    render inertia: "libraries/new"
  end

  def create
    account = current_identity_default_membership&.account
    unless account
      redirect_to new_library_path, alert: "Please complete your account setup first."
      return
    end

    library = Library.new(manual_library_params)
    library.account = account

    if library.save
      redirect_to "/libraries/#{library.slug}",
                  notice: "Library submitted successfully!"
    else
      redirect_to new_library_path, alert: library.errors.full_messages.join(", ")
    end
  end

  private

    def search_libraries(query)
      Library.search_by_query(query)
    end

    def library_props(library)
      {
        slug: library.slug,
        display_name: library.display_name,
        aliases: library.aliases,
        homepage_url: library.homepage_url,
        default_version: library.default_version,
        license_status: library.source_policy&.license_status,
        version_count: library.versions.size,
        page_count: library.versions.sum(&:pages_count),
        source_type: library.source_type,
        source_count: library.library_sources.size
      }
    end

    def version_props(version)
      {
        version: version.version,
        channel: version.channel,
        generated_at: version.generated_at&.iso8601,
        page_count: version.pages_count
      }
    end

    def page_props(page)
      {
        page_uid: page.page_uid,
        path: page.path,
        title: page.title,
        url: page.url,
        headings: page.headings || [],
        bytes: page.bytes,
        content: truncate_content(page.description)
      }
    end

    def truncate_content(content)
      return nil unless content
      content.length > 5000 ? "#{content[0, 5000]}..." : content
    end

    def library_meta_description(library)
      parts = [ library.display_name, "documentation" ]
      parts << "— #{library.versions.size} versions" if library.versions.size > 0
      parts << "and #{library.total_pages_count} pages" if library.total_pages_count > 0
      parts << "on ContextQMD. Install, search, and retrieve version-aware docs."
      parts.join(" ")
    end

    def manual_library_params
      permitted = params.expect(library: [ :slug, :display_name, :homepage_url, :default_version, aliases: [] ])
      slug = permitted[:slug].to_s.tr("_", "-").parameterize(separator: "-")

      permitted.merge(
        slug: slug,
        namespace: slug,
        name: slug
      )
    end
end
