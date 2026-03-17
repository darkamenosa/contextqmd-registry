# frozen_string_literal: true

require "rubygems"

class Version < ApplicationRecord
  belongs_to :library, counter_cache: true
  has_many :pages, dependent: :destroy
  has_many :bundles, dependent: :destroy
  has_one :fetch_recipe, dependent: :destroy

  validates :version, presence: true, uniqueness: { scope: :library_id }
  validates :channel, presence: true, inclusion: { in: %w[stable latest canary snapshot] }

  after_create_commit :update_library_stats
  after_destroy_commit :update_library_stats

  scope :ordered, -> { order(generated_at: :desc) }
  scope :stable, -> { where(channel: "stable") }

  # Fizzy-inspired reconciliation: fix pages_count drift after bulk operations.
  def reconcile_pages_count
    update_column :pages_count, pages.count
    update_library_stats
  end

  private

    def update_library_stats
      return if library.destroyed?

      library.update_columns(
        total_pages_count: library.versions.sum(:pages_count),
        latest_version_at: library.versions.maximum(:created_at)
      )
    end

    def self.channel_for(version_value)
      return "latest" if version_value.blank?

      lowered = version_value.to_s.downcase
      return "snapshot" if lowered.include?("snapshot")
      return "canary" if lowered.match?(/alpha|beta|canary|preview|nightly|rc|pre/)

      "stable"
    end

    def self.compare(version_a, version_b)
      parsed_a = parse(version_a)
      parsed_b = parse(version_b)
      return parsed_a <=> parsed_b if parsed_a && parsed_b

      version_a.to_s <=> version_b.to_s
    end

    def self.parse(version_value)
      return nil if version_value.blank?

      Gem::Version.new(version_value.to_s)
    rescue ArgumentError
      nil
    end
end
