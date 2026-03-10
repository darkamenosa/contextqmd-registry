# frozen_string_literal: true

class Libraries::PagesController < InertiaController
  allow_unauthenticated_access
  disallow_account_scope

  def show
    library = Library.includes(versions: :pages).find_by!(namespace: params[:namespace], name: params[:name])
    version = library.versions.find { |v| v.version == params[:version] }

    unless version
      redirect_to detail_libraries_path(namespace: library.namespace, name: library.name), alert: "Version not found"
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
        namespace: library.namespace,
        name: library.name,
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
