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
    libraries = libraries.includes(:source_policy, versions: [ :pages, :fetch_recipe ]).order(:namespace, :name)

    render inertia: "libraries/index", props: {
      libraries: libraries.map { |lib| library_props(lib) },
      query: params[:query] || ""
    }
  end

  def show
    library = Library.includes(versions: :pages, source_policy: []).find_by!(namespace: params[:namespace], name: params[:name])
    versions = library.versions.ordered

    # Pick the best version: requested > version with most pages > default > first
    selected_version = if params[:version].present?
      versions.find { |v| v.version == params[:version] }
    end
    selected_version ||= pick_best_version(versions, library.default_version)

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

    # Pick the version that gives users the best experience:
    # 1. The configured default_version if it has pages
    # 2. The version with the most pages (for crawled content)
    # 3. The first version
    def pick_best_version(versions, default_version_name)
      return nil if versions.empty?

      default_v = versions.find { |v| v.version == default_version_name }
      best_v = versions.max_by { |v| v.pages.size }

      # If the default has content, use it. Otherwise prefer the richest version.
      if default_v && default_v.pages.size > 0
        # But if another version has significantly more pages, prefer it
        if best_v && best_v.pages.size > default_v.pages.size * 3
          best_v
        else
          default_v
        end
      else
        best_v || versions.first
      end
    end

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
        source_type: library.versions.flat_map { |v| v.fetch_recipe&.source_type }.compact.first
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
      content.length > 1000 ? "#{content[0, 1000]}..." : content
    end

    def pagination_props(pagy)
      {
        page: pagy.page,
        per_page: pagy.limit,
        total: pagy.count,
        pages: pagy.last,
        from: pagy.from,
        to: pagy.to,
        has_previous: pagy.previous.present?,
        has_next: pagy.next.present?
      }
    end

    def library_params
      params.expect(library: [ :namespace, :name, :display_name, :homepage_url, :default_version, aliases: [] ])
    end
end
