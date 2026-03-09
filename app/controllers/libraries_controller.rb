# frozen_string_literal: true

class LibrariesController < InertiaController
  allow_unauthenticated_access
  disallow_account_scope

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

    render inertia: "libraries/show", props: {
      library: library_props(library),
      versions: versions.map { |v| version_props(v) }
    }
  rescue ActiveRecord::RecordNotFound
    redirect_to libraries_path, alert: "Library not found"
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
end
