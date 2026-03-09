# frozen_string_literal: true

class LibrariesController < InertiaController
  allow_unauthenticated_access
  disallow_account_scope
  before_action :authenticate_identity!, only: [ :new, :create ]

  def index
    libraries = if params[:query].present?
      search_libraries(params[:query])
    else
      Library.all
    end
    libraries = libraries.includes(:source_policy).order(:namespace, :name)

    render inertia: "libraries/index", props: {
      libraries: libraries.map { |lib| library_props(lib) },
      query: params[:query] || ""
    }
  end

  def show
    library = Library.includes(:versions, :source_policy).find_by!(namespace: params[:namespace], name: params[:name])
    versions = library.versions.ordered
    default_version = versions.find { |v| v.version == library.default_version } || versions.first
    pages = default_version ? default_version.pages.order(:path) : Page.none

    render inertia: "libraries/show", props: {
      library: library_props(library),
      versions: versions.map { |v| version_props(v) },
      pages: pages.map { |p| page_props(p) },
      default_version_label: default_version&.version
    }
  rescue ActiveRecord::RecordNotFound
    redirect_to libraries_path, alert: "Library not found"
  end

  def new
    render inertia: "libraries/new"
  end

  def create
    library = Library.new(library_params)
    # For now, assign a default account (first account of the identity)
    library.account = Current.identity.users.first&.account || Account.first

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
        license_status: library.source_policy&.license_status
      }
    end

    def version_props(version)
      {
        version: version.version,
        channel: version.channel,
        generated_at: version.generated_at&.iso8601,
        page_count: version.pages.count
      }
    end

    def page_props(page)
      {
        page_uid: page.page_uid,
        path: page.path,
        title: page.title,
        url: page.url,
        headings: page.headings,
        bytes: page.bytes
      }
    end

    def library_params
      params.expect(library: [ :namespace, :name, :display_name, :homepage_url, :default_version, aliases: [] ])
    end
end
