# frozen_string_literal: true

class Libraries::PagesController < InertiaController
  allow_unauthenticated_access
  disallow_account_scope

  def show
    library = Library.find_by!(slug: params[:slug])
    version = library.versions.find_by(version: params[:version])

    unless version
      redirect_to "/libraries/#{library.slug}", alert: "Version not found"
      return
    end

    page = version.pages.find_by!(page_uid: params[:page_uid])

    render inertia: "libraries/page-show", props: {
      library: library_summary(library),
      version: params[:version],
      page: full_page_props(page)
    }
  rescue ActiveRecord::RecordNotFound
    redirect_to libraries_path, alert: "Page not found"
  end

  private

    def library_summary(library)
      {
        slug: library.slug,
        display_name: library.display_name
      }
    end

    def full_page_props(page)
      {
        page_uid: page.page_uid,
        path: page.path,
        title: page.title,
        url: page.url,
        headings: page.headings || [],
        bytes: page.bytes,
        content: page.description
      }
    end
end
