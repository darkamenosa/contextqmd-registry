# frozen_string_literal: true

class LibrarySource < ApplicationRecord
  belongs_to :library
  has_many :crawl_requests, dependent: :nullify
  has_many :fetch_recipes, dependent: :nullify

  before_validation :normalize_url!

  validates :url, presence: true, uniqueness: true
  validates :source_type, presence: true
  validate :single_primary_source_per_library

  scope :active, -> { where(active: true) }
  scope :primary_first, -> { order(primary: :desc, updated_at: :desc) }

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

    def single_primary_source_per_library
      return unless primary?
      return unless library

      if library.library_sources.where(primary: true).where.not(id: id).exists?
        errors.add(:primary, "is already assigned for this library")
      end
    end
end
