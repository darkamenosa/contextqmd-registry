# frozen_string_literal: true

class ProcessCrawlRequestJob < ApplicationJob
  queue_as :default

  retry_on StandardError, wait: :polynomially_longer, attempts: 3

  def perform(crawl_request)
    return unless crawl_request.pending?

    crawl_request.start_processing!

    fetcher = DocsFetcher.for(crawl_request.source_type)
    result = fetcher.fetch(crawl_request.url)

    library = find_or_create_library(result, crawl_request)
    version = create_version(library, result)
    create_pages(version, result.pages)
    record_fetch_recipe(version, crawl_request)
    update_manifest_checksum!(version)

    library.update!(default_version: version.version) if library.default_version.blank?

    crawl_request.complete!(library)
  rescue StandardError => e
    crawl_request.fail!(e.message) if crawl_request.processing?
    raise
  end

  private

    def find_or_create_library(result, crawl_request)
      system_account = Account.find_or_create_by!(name: "ContextQMD System") { |a| a.personal = false }

      Library.find_or_create_by!(namespace: result.namespace, name: result.name) do |lib|
        lib.account = system_account
        lib.display_name = result.display_name
        lib.homepage_url = result.homepage_url
        lib.aliases = result.aliases
      end
    end

    def create_version(library, result)
      version_tag = result.version || "latest"
      version = library.versions.find_or_initialize_by(version: version_tag)
      version.channel = result.version ? "stable" : "latest"
      version.generated_at = Time.current
      version.save!
      version
    end

    def create_pages(version, pages)
      pages.each do |page_data|
        content = page_data[:content].to_s
        checksum = Digest::SHA256.hexdigest(content)

        page = version.pages.find_or_initialize_by(page_uid: page_data[:page_uid])
        page.assign_attributes(
          path: page_data[:path],
          title: page_data[:title],
          url: page_data[:url],
          description: content,
          bytes: content.bytesize,
          checksum: checksum,
          headings: page_data[:headings] || []
        )
        page.save!
      end
    end

    def record_fetch_recipe(version, crawl_request)
      recipe = version.fetch_recipe || version.build_fetch_recipe
      recipe.assign_attributes(
        source_type: crawl_request.source_type,
        url: crawl_request.url,
        normalizer_version: "1.0",
        splitter_version: "1.0"
      )
      recipe.save!
    end

    def update_manifest_checksum!(version)
      page_checksums = version.pages.order(:page_uid).pluck(:checksum).compact
      return if page_checksums.empty?

      manifest_checksum = Digest::SHA256.hexdigest(page_checksums.join)
      version.update!(manifest_checksum: manifest_checksum)
    end
end
