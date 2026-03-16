# frozen_string_literal: true

class HomepagesController < InertiaController
  allow_unauthenticated_access
  disallow_account_scope

  def show
    tab = params[:tab] || "popular"
    libraries = Library.includes(:versions).all
    sorted = sort_libraries(libraries, tab)

    render inertia: "pages/home", props: {
      library_count: libraries.size,
      libraries: sorted.first(10).map { |lib| home_library_props(lib) },
      active_tab: tab
    }
  end

  private

    def sort_libraries(libraries, tab)
      case tab
      when "recent"
        libraries.sort_by { |lib| -(lib.versions.map(&:created_at).max&.to_i || 0) }
      when "trending"
        libraries.select { |lib| lib.versions.sum(&:pages_count) > 0 }
          .sort_by { |lib| -(lib.versions.map(&:created_at).max&.to_i || 0) }
      else # "popular"
        libraries.sort_by { |lib| -lib.versions.sum(&:pages_count) }
      end
    end

    def home_library_props(library)
      best_version = library.versions.max_by(&:pages_count)
      latest_version = library.versions.max_by(&:created_at)
      {
        slug: library.slug,
        display_name: library.display_name,
        page_count: best_version&.pages_count || 0,
        source_type: library.source_type,
        homepage_url: library.homepage_url,
        updated_at: (latest_version&.created_at || library.updated_at).iso8601
      }
    end
end
