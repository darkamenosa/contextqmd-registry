# frozen_string_literal: true

class ProcessCrawlRequestJob < ApplicationJob
  queue_as :default

  # Mark as failed only after all retries are exhausted.
  # The block runs when retry_on gives up (after 3 attempts).
  retry_on StandardError, wait: :polynomially_longer, attempts: 3 do |job, error|
    crawl_request = job.arguments.first
    crawl_request&.fail!(error.message) unless crawl_request&.completed?
  end

  def perform(crawl_request)
    return unless crawl_request.pending? || crawl_request.processing?

    crawl_request.start_processing! if crawl_request.pending?

    fetcher = DocsFetcher.for(crawl_request.source_type)
    result = fetcher.fetch(crawl_request.url)

    library = find_or_create_library(result, crawl_request)
    version = create_version(library, result)
    create_pages(version, result.pages, source_type: crawl_request.source_type)
    record_fetch_recipe(version, crawl_request)
    update_manifest_checksum!(version)

    library.update!(default_version: version.version) if library.default_version.blank?

    crawl_request.complete!(library)
  end

  private

    def find_or_create_library(result, crawl_request)
      system_account = Account.find_or_create_by!(name: "ContextQMD System") { |a| a.personal = false }

      library = Library.find_or_create_by!(namespace: result.namespace, name: result.name) do |lib|
        lib.account = system_account
        lib.display_name = result.display_name
        lib.homepage_url = result.homepage_url
        lib.aliases = result.aliases
      end

      # Always update metadata on re-crawl (find_or_create_by! block only runs for new records)
      merged_aliases = ((library.aliases || []) + (result.aliases || [])).uniq
      library.update!(
        display_name: result.display_name.presence || library.display_name,
        aliases: merged_aliases,
        homepage_url: result.homepage_url.presence || library.homepage_url
      )

      library
    end

    def create_version(library, result)
      version_tag = result.version || "latest"
      version = library.versions.find_or_initialize_by(version: version_tag)
      version.channel = result.version ? "stable" : "latest"
      version.generated_at = Time.current
      version.save!
      version
    end

    def create_pages(version, pages, source_type: nil)
      incoming_uids = Set.new

      pages.each do |page_data|
        content = page_data[:content].to_s
        checksum = Digest::SHA256.hexdigest(content)
        uid = page_data[:page_uid]
        incoming_uids << uid

        page = version.pages.find_or_initialize_by(page_uid: uid)

        # Skip save if content hasn't changed (deduplication)
        next if page.persisted? && page.checksum == checksum

        page.assign_attributes(
          path: page_data[:path],
          title: page_data[:title],
          url: page_data[:url],
          description: content,
          bytes: content.bytesize,
          checksum: checksum,
          source_ref: source_type,
          headings: page_data[:headings] || []
        )
        page.save!
      end

      # Remove stale pages that no longer exist in the source
      version.pages.where.not(page_uid: incoming_uids.to_a).destroy_all if incoming_uids.any?
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
