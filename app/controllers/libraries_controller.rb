# frozen_string_literal: true

class LibrariesController < InertiaController
  include Pagy::Method

  LIST_CACHE_TTL = 5.minutes
  DETAIL_CACHE_TTL = 1.hour

  allow_unauthenticated_access
  disallow_account_scope
  before_action :authenticate_identity!, only: [ :new, :create ]

  def index
    query = params[:query].to_s.strip
    page = params[:page].presence || "1"
    cached = Rails.cache.fetch([ "public", "libraries", "index", query, page ], expires_in: LIST_CACHE_TTL) do
      libraries = if query.present?
        search_libraries(query).includes(:source_policy, :library_sources)
      else
        Library.includes(:source_policy, :library_sources).order(:slug)
      end

      pagy, paginated = pagy(:offset, libraries, limit: 10)

      {
        libraries: paginated.map { |lib| library_props(lib) },
        pagination: pagination_props(pagy),
        query: query
      }
    end

    render inertia: "libraries/index", props: {
      libraries: cached[:libraries],
      pagination: cached[:pagination],
      query: cached[:query],
      seo: seo_props(
        title: "Libraries",
        description: "Browse version-aware documentation packages for libraries. Search, install, and use with CLI or MCP.",
        url: canonical_url(allowed_params: [ :page ]),
        noindex: query.present? ? true : nil
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
    cached = Rails.cache.fetch(
      library_show_cache_key(
        library: library,
        versions: versions,
        selected_version: selected_version,
        pages: pages,
        pagination: pagination_props(pagy),
        search_query: search_query
      ),
      expires_in: DETAIL_CACHE_TTL
    ) do
      {
        library: library_props(library),
        versions: versions.map { |v| version_props(v) },
        pages: pages.map { |p| page_props(p) },
        selected_version: selected_version&.version,
        pagination: pagination_props(pagy),
        search: search_query,
        search_active: search_active
      }
    end

    render inertia: "libraries/show", props: {
      library: cached[:library],
      versions: cached[:versions],
      pages: cached[:pages],
      selected_version: cached[:selected_version],
      pagination: cached[:pagination],
      search: cached[:search],
      search_active: cached[:search_active],
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
        version_count: library.versions_count,
        page_count: library.total_pages_count,
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
      parts << "— #{library.versions_count} versions" if library.versions_count > 0
      parts << "and #{library.total_pages_count} pages" if library.total_pages_count > 0
      parts << "on ContextQMD. Install, search, and retrieve version-aware docs."
      parts.join(" ")
    end

    def library_show_cache_key(library:, versions:, selected_version:, pages:, pagination:, search_query:)
      versions_signature = versions.map do |version|
        [
          version.id,
          version.version,
          version.channel,
          version.pages_count,
          version.generated_at&.utc&.to_i,
          version.updated_at&.utc&.to_i
        ]
      end
      pages_signature = pages.map { |page| [ page.id, page.checksum ] }
      sources_signature = library.library_sources.map { |source| [ source.id, source.updated_at&.utc&.to_i ] }

      [
        "public",
        "libraries",
        "show",
        library.id,
        library.slug,
        library.display_name,
        library.homepage_url,
        library.default_version,
        library.source_type,
        library.total_pages_count,
        library.versions_count,
        library.aliases,
        library.source_policy&.cache_key_with_version,
        selected_version&.id,
        search_query,
        pagination,
        Digest::SHA256.hexdigest(versions_signature.to_json),
        Digest::SHA256.hexdigest(pages_signature.to_json),
        Digest::SHA256.hexdigest(sources_signature.to_json)
      ]
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
