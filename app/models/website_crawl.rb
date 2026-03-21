# frozen_string_literal: true

class WebsiteCrawl < ApplicationRecord
  STATUSES = %w[pending processing completed failed cancelled].freeze
  RUNNERS = %w[auto ruby node].freeze
  STAGED_STATE_RETENTION = 3.days

  belongs_to :crawl_request
  has_many :crawl_urls, class_name: "WebsiteCrawlUrl", dependent: :delete_all
  has_many :crawl_pages, class_name: "WebsiteCrawlPage", dependent: :delete_all

  enum :status, STATUSES.index_by(&:itself), default: :pending

  delegate :url, to: :crawl_request

  validates :runner, inclusion: { in: RUNNERS }

  scope :staged_state_expired, -> {
    where(status: %w[failed cancelled]).where(completed_at: ...STAGED_STATE_RETENTION.ago)
  }

  def self.start!(crawl_request)
    crawl = find_by(crawl_request: crawl_request)
    return crawl if crawl

    create!(crawl_request: crawl_request, runner: requested_runner_for(crawl_request)).tap(&:enqueue_processing!)
  end

  def self.requested_runner_for(crawl_request)
    metadata = crawl_request.metadata || {}
    requested = metadata["website_runner"] || metadata[:website_runner]
    requested = requested.to_s if requested
    requested.presence_in(RUNNERS) || "auto"
  end

  def self.cleanup_expired_staged_state_now
    staged_state_expired.find_each(&:cleanup_staged_state!)
  end

  def enqueue_processing!
    ProcessWebsiteCrawlJob.perform_later(self)
  end

  def prepare!
    with_lock do
      return false if terminal?
      return false if processing?

      self.runner = self.class.requested_runner_for(crawl_request) if runner.blank?
      self.status = "processing"
      self.started_at ||= Time.current
      self.error_message = nil
      save!
    end

    unless crawl_request.begin_processing!(message: "Starting website crawl")
      sync_request_terminal_state!
      return crawl_request.processing?
    end

    ensure_seed_url!
    true
  end

  def fetch_pending!(step)
    return if terminal?

    ensure_seed_url!

    loop do
      sync_request_terminal_state!
      break if terminal?
      break if crawl_limit_reached?

      crawl_url = next_pending_url
      break unless crawl_url

      if node_runner_active?
        fetch_node_batch!([ crawl_url ])
      else
        fetch_ruby_batch!([ crawl_url ])
      end

      # The persisted crawl_url state drives resumption; the cursor checkpoints
      # per-URL progress so Continuable can resume after interruptions/errors.
      step.set!(crawl_url.id)
    end

    return if terminal?
    raise DocsFetcher::PermanentFetchError, "No content found at #{url}" if crawl_pages.none?
  end

  def publish!
    sync_request_terminal_state!
    return if terminal?

    pages = WebsiteCrawlPageCollection.new(crawl_pages)
    first_page = pages.first
    raise DocsFetcher::PermanentFetchError, "No content found at #{url}" unless first_page

    identity = DocsFetcher::LibraryIdentity.from_website(uri: URI.parse(url), title: first_page[:title])
    result = CrawlResult.new(
      slug: identity[:slug],
      namespace: identity[:namespace],
      name: identity[:name],
      display_name: identity[:display_name],
      homepage_url: url,
      aliases: identity[:aliases],
      version: nil,
      pages: pages,
      complete: false
    )

    crawl_request.update_progress("Importing 0/#{pages.size} pages", current: 0, total: pages.size)

    CrawlRequest.transaction do
      library, source = CrawlImport.new(crawl_request).import!(result)
      crawl_request.mark_completed(library, source)
      update!(status: "completed", completed_at: Time.current, error_message: nil)
    end
  end

  def cleanup!
    return unless completed?

    cleanup_staged_state!
  end

  def cleanup_staged_state!
    crawl_pages.delete_all
    crawl_urls.delete_all
  end

  def fail!(message)
    crawl_request.reload
    crawl_request.mark_failed(message) unless crawl_request.terminal?
    mark_failed!(message)
  end

  def mark_failed!(message)
    return if completed? || failed?

    update!(status: "failed", error_message: message, completed_at: Time.current)
  end

  def mark_cancelled!
    return if completed? || cancelled?

    update!(status: "cancelled", error_message: nil, completed_at: Time.current)
  end

  def mark_pending_for_retry!
    return unless processing?

    update!(status: "pending", error_message: nil)
  end

  def resume_processing!
    return if terminal? || processing? || !pending?

    crawl_request.reload
    return unless crawl_request.processing?

    update!(status: "processing", error_message: nil)
  end

  def sync_request_terminal_state!
    crawl_request.reload

    if crawl_request.cancelled?
      mark_cancelled!
    elsif crawl_request.failed?
      mark_failed!(crawl_request.error_message.presence || "Crawl request failed")
    elsif crawl_request.completed?
      update!(status: "completed", completed_at: crawl_request.completed_at || Time.current, error_message: nil)
    end
  end

  def terminal?
    completed? || failed? || cancelled?
  end

  private

    def ensure_seed_url!
      upsert_urls!([ url ])
    end

    def fetch_ruby_batch!(urls)
      snapshots = ruby_runner.fetch_batch(crawl_request, urls.map(&:url))
      snapshots_by_requested_url = snapshots.index_by { |snapshot| snapshot[:requested_url] }

      urls.each do |crawl_url|
        snapshot = snapshots_by_requested_url[crawl_url.url]
        process_snapshot!(crawl_url, snapshot, allow_promotion: auto_runner? && crawl_pages.none?)
      end
    end

    def fetch_node_batch!(urls)
      snapshots = node_runner.fetch_batch(crawl_request, urls.map(&:url))
      snapshots_by_requested_url = snapshots.index_by { |snapshot| snapshot[:requested_url] }

      urls.each do |crawl_url|
        process_snapshot!(crawl_url, snapshots_by_requested_url[crawl_url.url], allow_promotion: false)
      end
    end

    def process_snapshot!(crawl_url, snapshot, allow_promotion:)
      if should_promote_to_node?(snapshot, allow_promotion: allow_promotion)
        promote_to_node!
        return
      end

      links = Array(snapshot&.dig(:links))
      upsert_urls!(links) if remaining_discovery_capacity != 0

      if snapshot&.dig(:page)
        store_page!(crawl_url, snapshot[:page])
        crawl_url.update!(status: "fetched", processed_at: Time.current)
      else
        crawl_url.update!(status: "skipped", processed_at: Time.current)
      end
      increment!(:processed_urls_count)

      crawl_request.update_progress(
        "Discovered #{discovered_urls_count} pages so far",
        current: self.processed_urls_count,
        total: crawl_limit
      )
    end

    def store_page!(crawl_url, page)
      record = crawl_url.website_crawl_page || crawl_pages.build(website_crawl_url: crawl_url)
      record.assign_attributes(
        page_uid: page[:page_uid],
        path: page[:path],
        title: page[:title],
        url: page[:url],
        content: page[:content],
        headings: page[:headings] || []
      )
      record.save!
    end

    def upsert_urls!(urls)
      capacity = remaining_discovery_capacity
      seen = {}
      rows = urls.filter_map do |raw_url|
        normalized = normalize_url(raw_url)
        next if normalized.blank?
        next if seen[normalized]

        seen[normalized] = true

        {
          website_crawl_id: id,
          url: raw_url,
          normalized_url: normalized,
          status: "pending",
          created_at: Time.current,
          updated_at: Time.current
        }
      end
      rows = rows.first(capacity) if capacity
      return if rows.empty?

      result = WebsiteCrawlUrl.insert_all(rows, unique_by: [ :website_crawl_id, :normalized_url ], returning: %w[id])
      increment!(:discovered_urls_count, result.rows.size) if result.rows.any?
    end

    def next_pending_url
      crawl_urls.pending.order(:id).first
    end

    def crawl_limit
      metadata = crawl_request.metadata || {}
      raw = metadata["website_max_pages"] || metadata[:website_max_pages]
      parsed = raw.to_i
      parsed.positive? ? parsed : nil
    end

    def crawl_limit_reached?
      crawl_limit.present? && self.processed_urls_count >= crawl_limit
    end

    def remaining_discovery_capacity
      return unless crawl_limit

      [ crawl_limit - discovered_urls_count, 0 ].max
    end

    def node_runner_active?
      runner == "node"
    end

    def auto_runner?
      runner == "auto"
    end

    def promote_to_node!
      return false unless auto_runner?
      return false unless node_runner.ready?

      update!(runner: "node")
      crawl_request.update_progress("Retrying with browser-rendered crawl")
      true
    end

    def should_promote_to_node?(snapshot, allow_promotion:)
      return false unless allow_promotion
      return false unless node_runner.ready?

      page = snapshot&.dig(:page)
      return true if page.nil?

      javascript_shell_page?(page)
    end

    def javascript_shell_page?(page)
      content = page[:content].to_s.strip
      return false if content.blank?

      headings = Array(page[:headings])
      DocsFetcher::Website::BROWSER_FALLBACK_PATTERNS.any? { |pattern| content.match?(pattern) } && headings.empty?
    end

    def normalize_url(url_string)
      uri = URI.parse(url_string)
      path = uri.path.to_s.chomp("/")
      path = "/" if path.empty?
      "#{uri.scheme}://#{uri.host&.downcase}#{path}"
    rescue URI::InvalidURIError
      nil
    end

    def ruby_runner
      @ruby_runner ||= DocsFetcher::Website::RubyRunner.new
    end

    def node_runner
      @node_runner ||= DocsFetcher::Website::NodeRunner.new
    end
end
