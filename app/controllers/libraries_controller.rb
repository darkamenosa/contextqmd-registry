# frozen_string_literal: true

class LibrariesController < InertiaController
  include Pagy::Method

  allow_unauthenticated_access
  disallow_account_scope
  before_action :authenticate_identity!, only: [ :new, :create ]

  def index
    libraries = if params[:query].present?
      search_libraries(params[:query])
    else
      Library.all
    end
    libraries = libraries.includes(:source_policy, versions: :pages).order(:namespace, :name)

    pagy, paginated = pagy(libraries, limit: 10)

    render inertia: "libraries/index", props: {
      libraries: paginated.map { |lib| library_props(lib) },
      pagination: pagination_props(pagy),
      query: params[:query] || ""
    }
  end

  def show
    library = Library.includes(versions: :pages, source_policy: []).find_by!(namespace: params[:namespace], name: params[:name])
    versions = library.versions.ordered

    selected_version = library.best_version(requested: params[:version])

    # Paginate pages for the selected version
    pages_scope = selected_version ? selected_version.pages : Page.none
    pages_scope = if params[:search].present?
      pages_scope.search_content(params[:search])
    else
      pages_scope.order(:path)
    end
    pagy, pages = pagy(pages_scope, limit: 30)

    render inertia: "libraries/show", props: {
      library: library_props(library),
      versions: versions.map { |v| version_props(v) },
      pages: pages.map { |p| page_props(p) },
      selected_version: selected_version&.version,
      pagination: pagination_props(pagy),
      search: params[:search] || ""
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

    library = Library.new(library_params)
    library.account = account

    if library.save
      redirect_to detail_libraries_path(namespace: library.namespace, name: library.name),
                  notice: "Library submitted successfully!"
    else
      redirect_to new_library_path, alert: library.errors.full_messages.join(", ")
    end
  end

  private

    def search_libraries(query)
      by_alias = Library.where("aliases @> ?", [ query ].to_json)
      return by_alias if by_alias.exists?

      Library.search_by_query(query)
    end

    def library_props(library)
      {
        namespace: library.namespace,
        name: library.name,
        display_name: library.display_name,
        aliases: library.aliases,
        homepage_url: library.homepage_url,
        default_version: library.default_version,
        license_status: library.source_policy&.license_status,
        version_count: library.versions.size,
        page_count: library.versions.sum { |v| v.pages.size },
        source_type: library.source_type
      }
    end

    def version_props(version)
      {
        version: version.version,
        channel: version.channel,
        generated_at: version.generated_at&.iso8601,
        page_count: version.pages.size
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

    def library_params
      params.expect(library: [ :namespace, :name, :display_name, :homepage_url, :default_version, aliases: [] ])
    end
end
