# frozen_string_literal: true

require "fileutils"

class Bundle < ApplicationRecord
  PATH_SAFE_PROFILE = /\A[a-z0-9\-]+\z/

  belongs_to :version
  has_one_attached :package, service: ->(bundle) { bundle.package_service_name }
  delegate :library, to: :version
  delegate :account, to: :library

  enum :status, %w[pending processing ready failed].index_by(&:itself), default: :ready
  enum :visibility, %w[public private].index_by(&:itself), default: :public, prefix: true

  before_validation :apply_defaults
  before_destroy :remember_file_path
  after_destroy_commit :remove_local_file

  validates :profile, presence: true,
    uniqueness: { scope: :version_id },
    format: { with: PATH_SAFE_PROFILE, message: "must be a path-safe slug" }
  validates :format, presence: true
  validates :sha256, presence: true, if: :ready?

  scope :ordered, -> { order(profile: :asc) }

  def build_later
    assign_attributes(
      status: :pending,
      sha256: nil,
      size_bytes: nil,
      error_message: nil
    )
    save!

    BuildBundleJob.perform_later(self)
  end

  def build_now
    update!(status: :processing, error_message: nil)
    DocsBundle.refresh!(version, profile: profile)
  rescue StandardError => e
    update!(status: :failed, error_message: e.message)
    raise
  end

  def file_path
    DocsBundle.path_for(version: version, profile: profile, format: format)
  end

  def filename
    "#{version.library.name}-#{version.version}-#{profile}.#{format}"
  end

  def available_locally?
    File.exist?(file_path)
  rescue ArgumentError
    false
  end

  def package_service_name
    if Rails.env.test?
      default_storage_service_name
    elsif visibility_public? && public_storage_enabled?
      :r2_public_assets
    elsif visibility_private? && private_storage_enabled?
      :r2_private_assets
    else
      default_storage_service_name
    end
  end

  def manifest_url
    public_package_url
  end

  def download_url(expires_in: 5.minutes)
    public_package_url || private_package_url(expires_in: expires_in)
  end

  def deliverable?
    package.attached? || available_locally?
  end

  def package_key(checksum:)
    [
      "bundles",
      visibility,
      version.library.namespace,
      version.library.name,
      version.version,
      profile,
      "#{checksum_value(checksum)}.#{format}"
    ].join("/")
  end

  private
    def checksum_value(checksum)
      checksum.to_s.delete_prefix("sha256:")
    end

    def public_package_url
      return unless package.attached?
      return unless visibility_public?
      return unless package_blob_record.service_name == "r2_public_assets"

      if public_asset_base_url.present?
        "#{public_asset_base_url}/#{package_blob_record.key}"
      else
        package.url(disposition: :attachment, filename: filename)
      end
    end

    def private_package_url(expires_in:)
      return unless package.attached?
      return unless visibility_private?
      return unless package_blob_record.service_name == "r2_private_assets"

      package.url(expires_in: expires_in, disposition: :attachment, filename: filename)
    end

    def package_blob_record
      package.blob
    end

    def public_storage_enabled?
      cloudflare_account_id.present? && cloudflare_public_bucket.present?
    end

    def private_storage_enabled?
      cloudflare_account_id.present? && cloudflare_private_bucket.present?
    end

    def default_storage_service_name
      Rails.application.config.active_storage.service&.to_sym || :local
    end

    def cloudflare_account_id
      ENV["CLOUDFLARE_ACCOUNT_ID"].presence || Rails.application.credentials.dig(:cloudflare, :account_id)
    end

    def cloudflare_public_bucket
      ENV["CLOUDFLARE_PUBLIC_BUCKET"].presence || Rails.application.credentials.dig(:cloudflare, :public_bucket)
    end

    def cloudflare_private_bucket
      ENV["CLOUDFLARE_PRIVATE_BUCKET"].presence || Rails.application.credentials.dig(:cloudflare, :private_bucket)
    end

    def public_asset_base_url
      ENV["CLOUDFLARE_PUBLIC_URL"].to_s.chomp("/").presence
    end

    def apply_defaults
      self.format ||= DocsBundle::FORMAT if profile.present?
    end

    def remember_file_path
      @file_path_to_remove = file_path.to_s if available_locally?
    end

    def remove_local_file
      return if @file_path_to_remove.blank?

      FileUtils.rm_f(@file_path_to_remove)
    end
end
