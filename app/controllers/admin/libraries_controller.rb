# frozen_string_literal: true

module Admin
  class LibrariesController < BaseController
    def index
      base = if params[:query].present?
        Library.search_by_query(params[:query])
      else
        Library.all
      end

      scope = base.includes(:account, :versions, :source_policy)

      pagy, libraries = pagy(
        scope.order(sort_column => sort_direction),
        limit: 25
      )

      render inertia: "admin/libraries/index", props: {
        libraries: libraries.map { |lib| library_row_props(lib) },
        pagination: pagination_props(pagy),
        total_count: Library.count,
        filters: {
          query: params[:query] || "",
          sort: params[:sort] || "updated_at",
          direction: params[:direction] || "desc"
        }
      }
    end

    def show
      library = Library.includes(:account, :source_policy, versions: :pages)
                       .find(params[:id])
      versions = library.versions.ordered
      crawl_requests = CrawlRequest.where(library: library).recent.limit(10)

      render inertia: "admin/libraries/show", props: {
        library: library_detail_props(library),
        versions: versions.map { |v| version_props(v) },
        crawl_requests: crawl_requests.map { |cr| crawl_props(cr) }
      }
    end

    def edit
      library = Library.includes(:versions).find(params[:id])

      render inertia: "admin/libraries/edit", props: {
        library: library_edit_props(library),
        versions: library.versions.ordered.pluck(:version)
      }
    end

    def update
      library = Library.find(params[:id])

      if library.update(library_params.merge(metadata_locked: true))
        redirect_to admin_library_path(library), notice: "Library updated."
      else
        redirect_to edit_admin_library_path(library),
                    alert: library.errors.full_messages.join(", ")
      end
    end

    def destroy
      library = Library.find(params[:id])

      # Nullify crawl_request references before destroying
      CrawlRequest.where(library: library).update_all(library_id: nil)

      library.destroy!
      redirect_to admin_libraries_path, notice: "Library \"#{library.display_name}\" deleted."
    end

    private

      def sort_column
        %w[slug display_name updated_at created_at].include?(params[:sort]) ? params[:sort] : "updated_at"
      end

      def sort_direction
        %w[asc desc].include?(params[:direction]) ? params[:direction] : "desc"
      end

      def library_params
        permitted = params.expect(library: [ :slug, :display_name, :homepage_url, :default_version, aliases: [] ])

        # Merge crawl_rules from separate form fields (one entry per line, textarea)
        if params[:library]&.key?(:crawl_rules)
          rules = {}
          cr = params[:library][:crawl_rules]
          %w[git_include_prefixes git_include_basenames git_exclude_prefixes git_exclude_basenames website_exclude_path_prefixes].each do |key|
            next unless cr&.key?(key)
            rules[key] = cr[key].to_s.split("\n").map(&:strip).reject(&:blank?)
          end
          permitted[:crawl_rules] = rules
        end

        permitted
      end

      def library_row_props(library)
        {
          id: library.id,
          slug: library.slug,
          namespace: library.namespace,
          name: library.name,
          display_name: library.display_name,
          homepage_url: library.homepage_url,
          default_version: library.default_version,
          license_status: library.source_policy&.license_status,
          version_count: library.versions.size,
          page_count: library.versions.sum { |v| v.pages.size },
          account_name: library.account.name,
          updated_at: library.updated_at.iso8601,
          created_at: library.created_at.iso8601
        }
      end

      def library_detail_props(library)
        last_crawl = CrawlRequest.where(library: library).completed.recent.first
        {
          id: library.id,
          slug: library.slug,
          namespace: library.namespace,
          name: library.name,
          display_name: library.display_name,
          homepage_url: library.homepage_url,
          default_version: library.default_version,
          source_type: library.source_type,
          aliases: library.aliases,
          license_status: library.source_policy&.license_status,
          account_name: library.account.name,
          version_count: library.versions.size,
          page_count: library.versions.sum { |v| v.pages.size },
          last_crawl_url: last_crawl&.url,
          crawl_rules: library.crawl_rules || {},
          created_at: library.created_at.iso8601,
          updated_at: library.updated_at.iso8601
        }
      end

      def library_edit_props(library)
        {
          id: library.id,
          slug: library.slug,
          namespace: library.namespace,
          name: library.name,
          display_name: library.display_name,
          homepage_url: library.homepage_url,
          default_version: library.default_version,
          source_type: library.source_type,
          aliases: library.aliases,
          metadata_locked: library.metadata_locked,
          crawl_rules: library.crawl_rules || {}
        }
      end

      def version_props(version)
        {
          id: version.id,
          version: version.version,
          channel: version.channel,
          generated_at: version.generated_at&.iso8601,
          page_count: version.pages.size,
          created_at: version.created_at.iso8601
        }
      end

      def crawl_props(cr)
        {
          id: cr.id,
          url: cr.url,
          source_type: cr.source_type,
          status: cr.status,
          error_message: cr.error_message,
          created_at: cr.created_at.iso8601
        }
      end
  end
end
