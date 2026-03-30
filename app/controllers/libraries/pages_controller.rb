# frozen_string_literal: true

class Libraries::PagesController < InertiaController
  allow_unauthenticated_access
  disallow_account_scope

  CACHE_TTL = 1.hour

  def show
    library = Library.find_by!(slug: params[:slug])
    version = library.versions.find_by(version: params[:version])

    unless version
      redirect_to "/libraries/#{library.slug}", alert: "Version not found"
      return
    end

    page = version.pages.find_by!(page_uid: params[:page_uid])
    return unless apply_public_cache_headers(library:, version:, page:)

    cached = Rails.cache.fetch(
      [
        "public",
        "library-page",
        library.id,
        library.display_name,
        params[:version],
        page.id,
        page.checksum
      ],
      expires_in: CACHE_TTL
    ) do
      {
        library: library_summary(library),
        version: params[:version],
        page: full_page_props(page),
        meta_description: page_meta_description(page, library)
      }
    end

    render inertia: "libraries/page-show", props: {
      library: cached[:library],
      version: cached[:version],
      page: cached[:page],
      seo: seo_props(
        title: "#{page.title} - #{library.display_name}",
        description: cached[:meta_description],
        url: canonical_url
      ),
      json_ld: breadcrumb_json_ld([
        { name: "Libraries", url: "https://#{canonical_host}/libraries" },
        { name: library.display_name, url: "https://#{canonical_host}/libraries/#{library.slug}" },
        { name: page.title, url: canonical_url }
      ])
    }
  rescue ActiveRecord::RecordNotFound
    redirect_to libraries_path, alert: "Page not found"
  end

  private

    def apply_public_cache_headers(library:, version:, page:)
      return true if request.inertia?

      expires_in CACHE_TTL, public: true

      stale?(
        etag: [
          "library-page",
          library.cache_key_with_version,
          version.cache_key_with_version,
          page.cache_key_with_version,
          params[:version]
        ],
        last_modified: [ library.updated_at, version.updated_at, page.updated_at ].compact.max,
        public: true
      )
    end

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
