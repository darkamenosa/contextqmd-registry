# frozen_string_literal: true

require "fileutils"

module ContextqmdDevTasks
  DEFAULT_CRAWL_URLS = [
    "https://github.com/rails/rails",
    "https://github.com/inertiajs/inertia-rails",
    "https://github.com/elmassimo/vite_ruby",
    "https://github.com/reactjs/react.dev",
    "https://github.com/vercel/next.js",
    "https://github.com/expressjs/expressjs.com"
  ].freeze

  module_function

  def reset_catalog!(out: $stdout)
    crawl_count = CrawlRequest.count
    library_count = Library.count

    CrawlRequest.delete_all
    Library.find_each(&:destroy!)
    FileUtils.rm_rf(DocsBundle.storage_root)

    out.puts "Removed #{crawl_count} crawl requests and #{library_count} libraries."
  end

  def submit_catalog!(out: $stdout)
    identity = submitter_identity!
    entries = crawl_entries

    entries.each do |entry|
      crawl_request = identity.crawl_requests.create!(
        url: entry.fetch(:url),
        metadata: entry.fetch(:metadata, {})
      )
      out.puts "Queued crawl ##{crawl_request.id}: #{crawl_request.url}"
    end
  end

  def refresh_catalog!(out: $stdout)
    reset_catalog!(out: out)
    submit_catalog!(out: out)
  end

  def crawl_urls
    raw = ENV["URLS"].to_s
    urls = raw.split(",").map(&:strip).reject(&:blank?)
    urls.presence || DEFAULT_CRAWL_URLS
  end

  def crawl_entries
    catalog_tsv = ENV["CATALOG_TSV"].to_s.strip
    return crawl_entries_from_catalog_tsv(catalog_tsv) if catalog_tsv.present?

    crawl_urls.map { |url| { url: url, metadata: {} } }
  end

  def crawl_entries_from_catalog_tsv(path)
    File.readlines(path, chomp: true).filter_map do |line|
      next if line.blank?

      slug, display_name, url = line.split("\t", 3)
      raise ArgumentError, "Invalid catalog row: #{line.inspect}" if url.blank?

      {
        url: url,
        metadata: {
          "canonical_slug" => slug.to_s.strip,
          "canonical_display_name" => display_name.to_s.strip
        }.reject { |_key, value| value.blank? }
      }
    end
  end

  def submitter_identity!
    email = ENV["SUBMITTER_EMAIL"].to_s.strip
    identity = if email.present?
      Identity.find_by(email: email)
    else
      Identity.where(staff: true).order(:id).first || Identity.order(:id).first
    end

    return identity if identity.present?

    raise <<~MESSAGE
      No submitter identity found.
      Create a local identity first or pass SUBMITTER_EMAIL=you@example.com.
    MESSAGE
  end
end

namespace :contextqmd do
  namespace :dev do
    desc "Delete local docs catalog data and bundle files"
    task reset_catalog: :environment do
      ContextqmdDevTasks.reset_catalog!
    end

    desc "Queue the default local crawl catalog (override with URLS=... and SUBMITTER_EMAIL=...)"
    task submit_catalog: :environment do
      ContextqmdDevTasks.submit_catalog!
    end

    desc "Reset local docs catalog data, then queue a fresh crawl catalog"
    task refresh_catalog: :environment do
      ContextqmdDevTasks.refresh_catalog!
    end
  end
end
