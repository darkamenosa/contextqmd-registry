# frozen_string_literal: true

class LibrarySource < ApplicationRecord
  VERSION_CHECKABLE_SOURCE_TYPES = %w[github gitlab bitbucket git llms_txt openapi website].freeze
  VERSION_CHECK_CLAIM_TIMEOUT = 30.minutes
  HOT_VERSION_CHECK_WINDOW = 30.days
  HOT_VERSION_CHECK_INTERVAL = 1.day
  NORMAL_VERSION_CHECK_INTERVAL = 7.days
  COLD_VERSION_CHECK_INTERVAL = 30.days
  COLD_VERSION_CHECK_THRESHOLD = 12
  VERSION_CHECK_JITTER_MAX = 12.hours
  DEFAULT_VERSION_CHECK_BUNDLE_VISIBILITY = "public"

  belongs_to :library
  has_many :crawl_requests, dependent: :nullify
  has_many :fetch_recipes, dependent: :nullify

  before_validation :normalize_url!
  before_validation :initialize_version_check_schedule, on: :create

  validates :url, presence: true, uniqueness: true
  validates :source_type, presence: true
  validate :single_primary_source_per_library

  scope :active, -> { where(active: true) }
  scope :primary, -> { where(primary: true) }
  scope :primary_first, -> { order(primary: :desc, updated_at: :desc) }
  scope :version_checkable, -> { where(source_type: VERSION_CHECKABLE_SOURCE_TYPES) }
  scope :version_check_due, lambda { |now = Time.current|
    active
      .primary
      .version_checkable
      .where("next_version_check_at IS NULL OR next_version_check_at <= ?", now)
      .where("version_check_claimed_at IS NULL OR version_check_claimed_at <= ?", now - VERSION_CHECK_CLAIM_TIMEOUT)
  }

  def self.find_matching(url:, source_type:)
    normalized = normalize_url(url, source_type: source_type)
    exact = find_by(url: normalized)
    return exact if exact

    active.find do |source|
      normalize_url(source.url, source_type: source.source_type) == normalized
    end
  end

  def self.normalize_url(url, source_type:)
    return if url.blank?

    uri = URI.parse(url.to_s.strip)
    host = uri.host.to_s.downcase
    scheme = uri.scheme.to_s.downcase.presence || "https"

    if git_source?(source_type, host)
      path = normalize_git_path(uri, host: host)
      return "#{scheme}://#{host}/#{path}" if path.present?
    end

    path = uri.path.to_s.sub(%r{/+\z}, "")
    query = uri.query.present? ? "?#{uri.query}" : ""
    path.present? ? "#{scheme}://#{host}#{path}#{query}" : "#{scheme}://#{host}#{query}"
  rescue URI::InvalidURIError
    url.to_s.strip
  end

  def version_checkable?
    source_type.to_s.in?(VERSION_CHECKABLE_SOURCE_TYPES)
  end

  def version_check_bucket
    if last_version_change_at.present? && last_version_change_at >= HOT_VERSION_CHECK_WINDOW.ago
      "hot"
    elsif consecutive_no_change_checks.to_i >= COLD_VERSION_CHECK_THRESHOLD
      "cold"
    else
      "normal"
    end
  end

  def version_check_interval
    return COLD_VERSION_CHECK_INTERVAL if source_type == "website" && last_version_change_at.blank?

    case version_check_bucket
    when "hot"
      HOT_VERSION_CHECK_INTERVAL
    when "cold"
      COLD_VERSION_CHECK_INTERVAL
    else
      NORMAL_VERSION_CHECK_INTERVAL
    end
  end

  def version_check_due?(now: Time.current)
    active? &&
      primary? &&
      version_checkable? &&
      (next_version_check_at.blank? || next_version_check_at <= now) &&
      (version_check_claimed_at.blank? || version_check_claimed_at <= now - VERSION_CHECK_CLAIM_TIMEOUT)
  end

  def claim_version_check!(now: Time.current)
    with_lock do
      reload
      return false unless version_check_due?(now: now)

      update!(version_check_claimed_at: now)
      true
    end
  end

  def enqueue_version_check!(now: Time.current)
    return false unless claim_version_check!(now: now)

    CheckLibrarySourceJob.perform_later(self)
    true
  rescue StandardError
    clear_version_check_claim!
    raise
  end

  def check_for_new_version!(now: Time.current)
    probe = DocsFetcher.for(source_type).probe_version(url)

    with_lock do
      reload

      if probe.blank?
        record_version_check_no_change!(now: now)
        return nil
      end

      if probe[:version].present?
        handle_version_probe!(probe: probe, now: now)
      elsif probe[:signature].present?
        handle_signature_probe!(probe: probe, now: now)
      else
        record_version_check_no_change!(now: now)
      end
    end
  rescue DocsFetcher::TransientFetchError
    record_version_check_failure!(now: now)
    raise
  rescue StandardError
    clear_version_check_claim!
    raise
  end

  def queue_version_refresh!(probe:, now: Time.current)
    detected_version = probe[:version].to_s
    detected_ref = probe[:ref].presence

    if active_version_refresh_exists?(detected_version)
      record_version_change_detected!(now: now)
      return nil
    end

    crawl_requests.create!(
      identity: CrawlRequest.system_identity,
      library: library,
      url: probe[:crawl_url].presence || url,
      source_type: source_type,
      requested_bundle_visibility: DEFAULT_VERSION_CHECK_BUNDLE_VISIBILITY,
      metadata: {
        "refresh_reason" => "version_check",
        "detected_version" => detected_version,
        "detected_ref" => detected_ref
      }.compact
    )

    update!(
      last_version_check_at: now,
      last_version_change_at: now,
      consecutive_no_change_checks: 0,
      next_version_check_at: reschedule_version_check_at(now, HOT_VERSION_CHECK_INTERVAL),
      version_check_claimed_at: nil
    )
  end

  def clear_version_check_claim!
    update_columns(version_check_claimed_at: nil, updated_at: Time.current)
  end

  def self.git_source?(source_type, host)
    source_type.to_s.in?(%w[github gitlab bitbucket git]) || host == "github.com" || host == "bitbucket.org" || host.include?("gitlab")
  end

  def self.normalize_git_path(uri, host:)
    raw_path = uri.path.to_s.delete_prefix("/").sub(%r{/+\z}, "").delete_suffix(".git")

    cleaned = if host == "github.com"
      raw_path.sub(%r{/(?:tree|blob)/.*\z}, "")
    elsif host.include?("gitlab")
      raw_path.sub(%r{/-/.*\z}, "")
    elsif host == "bitbucket.org"
      raw_path.sub(%r{/src/.*\z}, "")
    else
      raw_path.sub(%r{/(?:tree|blob|src)/.*\z}, "")
    end

    parts = cleaned.split("/").reject(&:blank?)
    return if parts.empty?

    if host.include?("gitlab")
      "#{parts[0...-1].join('/')}/#{parts[-1]}"
    elsif parts.size >= 2
      parts.first(2).join("/")
    else
      cleaned
    end
  end

  private

    def normalize_url!
      self.url = self.class.normalize_url(url, source_type: source_type) if url.present?
    end

    def initialize_version_check_schedule
      return unless version_checkable?
      return if next_version_check_at.present?

      self.next_version_check_at = reschedule_version_check_at(Time.current, initial_version_check_interval)
      self.consecutive_no_change_checks ||= 0
    end

    def single_primary_source_per_library
      return unless primary?
      return unless library

      if library.library_sources.where(primary: true).where.not(id: id).exists?
        errors.add(:primary, "is already assigned for this library")
      end
    end

    def latest_stable_version
      library.versions.stable.to_a.max { |left, right| Version.compare(left.version, right.version) }
    end

    def active_version_refresh_exists?(detected_version)
      crawl_requests
        .where(status: %w[pending processing])
        .where("metadata ->> 'detected_version' = ?", detected_version)
        .exists?
    end

    def active_signature_refresh_exists?(detected_signature)
      crawl_requests
        .where(status: %w[pending processing])
        .where("metadata ->> 'detected_signature' = ?", detected_signature)
        .exists?
    end

    def record_version_check_no_change!(now:)
      update!(
        last_version_check_at: now,
        consecutive_no_change_checks: consecutive_no_change_checks.to_i + 1,
        next_version_check_at: reschedule_version_check_at(now, version_check_interval),
        version_check_claimed_at: nil
      )
    end

    def record_version_check_failure!(now:)
      update!(
        last_version_check_at: now,
        next_version_check_at: reschedule_version_check_at(now, HOT_VERSION_CHECK_INTERVAL),
        version_check_claimed_at: nil
      )
    end

    def record_version_change_detected!(now:)
      update!(
        last_version_check_at: now,
        last_version_change_at: now,
        consecutive_no_change_checks: 0,
        next_version_check_at: reschedule_version_check_at(now, HOT_VERSION_CHECK_INTERVAL),
        version_check_claimed_at: nil
      )
    end

    def handle_version_probe!(probe:, now:)
      detected_version = probe[:version].to_s
      if library.versions.exists?(version: detected_version)
        record_version_check_no_change!(now: now)
        return nil
      end

      current_stable = latest_stable_version
      comparison = current_stable ? Version.compare(detected_version, current_stable.version) : 1

      if comparison.nil? || comparison.positive?
        queue_version_refresh!(probe: probe, now: now)
      else
        record_version_check_no_change!(now: now)
      end
    end

    def handle_signature_probe!(probe:, now:)
      detected_signature = probe[:signature].to_s

      if last_probe_signature.blank?
        record_signature_baseline!(detected_signature, now: now)
      elsif last_probe_signature == detected_signature
        record_signature_no_change!(detected_signature, now: now)
      elsif active_signature_refresh_exists?(detected_signature)
        record_signature_change_detected!(detected_signature, now: now)
      else
        queue_signature_refresh!(probe: probe, detected_signature: detected_signature, now: now)
      end
    end

    def queue_signature_refresh!(probe:, detected_signature:, now:)
      crawl_requests.create!(
        identity: CrawlRequest.system_identity,
        library: library,
        url: probe[:crawl_url].presence || url,
        source_type: source_type,
        requested_bundle_visibility: DEFAULT_VERSION_CHECK_BUNDLE_VISIBILITY,
        metadata: {
          "refresh_reason" => "content_check",
          "detected_signature" => detected_signature
        }
      )

      update!(
        last_version_check_at: now,
        last_version_change_at: now,
        last_probe_signature: detected_signature,
        consecutive_no_change_checks: 0,
        next_version_check_at: reschedule_version_check_at(now, HOT_VERSION_CHECK_INTERVAL),
        version_check_claimed_at: nil
      )
    end

    def record_signature_baseline!(detected_signature, now:)
      update!(
        last_version_check_at: now,
        last_probe_signature: detected_signature,
        consecutive_no_change_checks: consecutive_no_change_checks.to_i + 1,
        next_version_check_at: reschedule_version_check_at(now, version_check_interval),
        version_check_claimed_at: nil
      )
    end

    def record_signature_no_change!(detected_signature, now:)
      update!(
        last_version_check_at: now,
        last_probe_signature: detected_signature,
        consecutive_no_change_checks: consecutive_no_change_checks.to_i + 1,
        next_version_check_at: reschedule_version_check_at(now, version_check_interval),
        version_check_claimed_at: nil
      )
    end

    def record_signature_change_detected!(detected_signature, now:)
      update!(
        last_version_check_at: now,
        last_version_change_at: now,
        last_probe_signature: detected_signature,
        consecutive_no_change_checks: 0,
        next_version_check_at: reschedule_version_check_at(now, HOT_VERSION_CHECK_INTERVAL),
        version_check_claimed_at: nil
      )
    end

    def initial_version_check_interval
      source_type == "website" ? COLD_VERSION_CHECK_INTERVAL : NORMAL_VERSION_CHECK_INTERVAL
    end

    def reschedule_version_check_at(base_time, interval)
      base_time + interval + rand(VERSION_CHECK_JITTER_MAX)
    end
end
