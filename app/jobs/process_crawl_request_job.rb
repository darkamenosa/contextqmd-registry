# frozen_string_literal: true

class ProcessCrawlRequestJob < ApplicationJob
  queue_as :default

  # Mark as failed only after all retries are exhausted.
  # High attempt count ensures transient failures (rate limits, timeouts) don't drop requests.
  retry_on StandardError, wait: :polynomially_longer, attempts: 10 do |job, error|
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

    if library.default_version.blank? || !library.versions.exists?(version: library.default_version)
      library.update!(default_version: version.version)
    end

    crawl_request.complete!(library)
  end

  private

    def find_or_create_library(result, crawl_request)
      system_account = Account.find_or_create_by!(name: "ContextQMD System") { |a| a.personal = false }

      # 1. Exact namespace/name match
      library = Library.find_by(namespace: result.namespace, name: result.name)

      # 2. Try alias match — same lib crawled from different sources
      #    (e.g. GitHub aliases=["stimulus"] matches website namespace="stimulus")
      unless library
        candidates = (result.aliases || []) + [ result.name ]
        candidates.each do |candidate|
          library = Library.where("aliases @> ?", [ candidate ].to_json).first
          break if library
        end
      end

      # 4. Create new library if no match found
      library ||= Library.create!(
        account: system_account,
        namespace: result.namespace,
        name: result.name,
        display_name: result.display_name,
        homepage_url: result.homepage_url,
        aliases: result.aliases
      )

      # Always update metadata on re-crawl
      merged_aliases = ((library.aliases || []) + (result.aliases || []) + [ result.name ]).uniq
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
        content = sanitize_content(page_data[:content].to_s)
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
          headings: sanitize_headings(page_data[:headings] || [])
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

    # Strip prompt-injection XML tags that upstream docs sometimes include.
    # Removes only the tags, preserving text content between them.
    STRIP_TAGS = %w[SYSTEM system-reminder system_reminder IMPORTANT].freeze

    def sanitize_content(content)
      STRIP_TAGS.each do |tag|
        content = content.gsub(%r{</?#{Regexp.escape(tag)}[^>]*>}i, "")
      end
      # Strip JSX comment syntax {/*...*/} commonly found in React docs
      content = content.gsub(/\s*\{\/\*.*?\*\/\}/, "")
      content.strip
    end

    def sanitize_headings(headings)
      headings.map { |h| h.gsub(/\s*\{\/\*.*?\*\/\}/, "").strip }.reject(&:blank?)
    end

    def update_manifest_checksum!(version)
      page_checksums = version.pages.order(:page_uid).pluck(:checksum).compact
      return if page_checksums.empty?

      manifest_checksum = Digest::SHA256.hexdigest(page_checksums.join)
      version.update!(manifest_checksum: manifest_checksum)
    end
end
