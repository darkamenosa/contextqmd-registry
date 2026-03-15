# frozen_string_literal: true

class HomepagesController < InertiaController
  include Pagy::Method

  allow_unauthenticated_access
  disallow_account_scope

  def show
    libraries = Library.includes(versions: :pages).all
    sorted = sort_libraries(libraries, params[:tab] || "popular")
    pagy, paginated = pagy(sorted.map { |lib| home_library_props(lib) }, limit: 10)

    render inertia: "pages/home", props: {
      library_count: Library.count,
      libraries: paginated,
      pagination: pagination_props(pagy),
      active_tab: params[:tab] || "popular"
    }
  end

  private

    def sort_libraries(libraries, tab)
      case tab
      when "recent"
        libraries.sort_by { |lib| -(lib.versions.map(&:created_at).max&.to_i || 0) }
      when "trending"
        libraries.select { |lib| lib.versions.sum { |v| v.pages.size } > 0 }
          .sort_by { |lib| -(lib.versions.map(&:created_at).max&.to_i || 0) }
      else # "popular"
        libraries.sort_by { |lib| -lib.versions.sum { |v| v.pages.size } }
      end
    end

    def home_library_props(library)
      best_version = library.versions.max_by { |v| v.pages.size }
      latest_version = library.versions.max_by(&:created_at)
      {
        namespace: library.namespace,
        name: library.name,
        display_name: library.display_name,
        page_count: best_version&.pages&.size || 0,
        source_type: library.source_type,
        homepage_url: library.homepage_url,
        updated_at: (latest_version&.created_at || library.updated_at).iso8601
      }
    end
end
