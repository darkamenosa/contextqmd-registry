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
      page: full_page_props(page),
      seo: seo_props(
        title: "#{page.title} - #{library.display_name}",
        description: page_meta_description(page, library),
        url: canonical_url
      )
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

    def page_meta_description(page, library)
      snippet = page.description.to_s.gsub(/[#*`\[\]\n]/, " ").squish.truncate(140, omission: "...")
      snippet.present? ? "#{snippet} — #{library.display_name} docs on ContextQMD." : "#{page.title} — #{library.display_name} documentation on ContextQMD."
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
