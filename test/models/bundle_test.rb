# frozen_string_literal: true

require "test_helper"
require "fileutils"

class BundleTest < ActiveSupport::TestCase
  fixtures :accounts, :libraries, :versions, :bundles

  teardown do
    FileUtils.rm_rf(DocsBundle.storage_root)
  end

  test "valid bundle" do
    bundle = Bundle.new(
      version: versions(:nextjs_stable),
      profile: "compact",
      format: "tar.zst",
      sha256: "sha256:abc123def456"
    )
    assert bundle.valid?
  end

  test "defaults visibility to public" do
    bundle = Bundle.new(
      version: versions(:nextjs_stable),
      profile: "compact",
      format: "tar.gz",
      sha256: "sha256:abc123def456"
    )

    assert bundle.valid?
    assert_equal "public", bundle.visibility
  end

  test "requires profile" do
    bundle = Bundle.new(version: versions(:nextjs_stable), format: "tar.zst", sha256: "sha256:abc")
    assert_not bundle.valid?
    assert bundle.errors[:profile].present?
  end

  test "profile must be path-safe" do
    bundle = Bundle.new(
      version: versions(:nextjs_stable),
      profile: "../etc/passwd",
      format: "tar.gz",
      sha256: "sha256:abc123"
    )

    assert_not bundle.valid?
    assert_includes bundle.errors[:profile], "must be a path-safe slug"
  end

  test "defaults format to tar.gz" do
    bundle = Bundle.new(version: versions(:nextjs_stable), profile: "compact", sha256: "sha256:abc")
    assert bundle.valid?
    assert_equal "tar.gz", bundle.format
  end

  test "requires sha256" do
    bundle = Bundle.new(version: versions(:nextjs_stable), profile: "full", format: "tar.zst")
    assert_not bundle.valid?
    assert bundle.errors[:sha256].present?
  end

  test "profile is unique per version" do
    # slim fixture already exists
    duplicate = Bundle.new(
      version: versions(:nextjs_stable),
      profile: "slim",
      format: "tar.zst",
      sha256: "sha256:different"
    )
    assert_not duplicate.valid?
    assert duplicate.errors[:profile].present?
  end

  test "same profile allowed on different versions" do
    bundle = Bundle.new(
      version: versions(:rails_stable),
      profile: "slim",
      format: "tar.zst",
      sha256: "sha256:rails_slim"
    )
    assert bundle.valid?
  end

  test "belongs to version" do
    bundle = bundles(:nextjs_slim)
    assert_equal versions(:nextjs_stable), bundle.version
  end

  test "destroy removes local bundle file" do
    version = versions(:nextjs_stable)
    bundle = DocsBundle.refresh!(version, profile: "full")

    assert File.exist?(bundle.file_path), "Expected bundle file to exist before destroy"

    bundle.destroy!

    assert_not File.exist?(bundle.file_path), "Expected bundle file to be deleted on destroy"
  end

  test "package_service_name falls back to the configured test service" do
    bundle = Bundle.new(
      version: versions(:nextjs_stable),
      profile: "full",
      visibility: "private"
    )

    assert_equal :test, bundle.package_service_name
  end

  test "package_service_name uses the public R2 service outside test when configured" do
    bundle = Bundle.new(
      version: versions(:nextjs_stable),
      profile: "full",
      visibility: "public"
    )

    original_env = Rails.env
    Rails.singleton_class.define_method(:env) { ActiveSupport::StringInquirer.new("development") }
    bundle.define_singleton_method(:public_storage_enabled?) { true }

    begin
      assert_equal :r2_public_assets, bundle.package_service_name
    ensure
      Rails.singleton_class.define_method(:env) { original_env }
    end
  end

  test "manifest_url uses the public package URL when the package is published to the public bucket" do
    bundle = bundles(:nextjs_full)
    fake_blob = Struct.new(:service_name, :key).new("r2_public_assets", "bundle-key")
    fake_package = Object.new
    fake_package.define_singleton_method(:attached?) { true }
    fake_package.define_singleton_method(:blob) { fake_blob }

    bundle.update!(visibility: "public")
    bundle.define_singleton_method(:package) { fake_package }

    expected_url = "#{ENV.fetch("CLOUDFLARE_PUBLIC_URL")}/bundle-key"
    assert_equal expected_url, bundle.manifest_url
  end

  test "download_url uses a signed private package URL when the bundle is private" do
    bundle = bundles(:nextjs_full)
    fake_blob = Struct.new(:service_name).new("r2_private_assets")
    fake_package = Object.new
    fake_package.define_singleton_method(:attached?) { true }
    fake_package.define_singleton_method(:blob) { fake_blob }
    fake_package.define_singleton_method(:url) do |**options|
      raise "expected attachment download" unless options[:disposition] == :attachment

      "https://private.example.com/downloads/bundle"
    end

    bundle.update!(visibility: "private")
    bundle.define_singleton_method(:package) { fake_package }

    assert_equal "https://private.example.com/downloads/bundle", bundle.download_url
  end

  test "package_key uses a deterministic checksum-based path" do
    bundle = Bundle.new(
      version: versions(:nextjs_stable),
      profile: "full",
      format: "tar.gz",
      visibility: "public"
    )

    assert_equal(
      "bundles/public/vercel/nextjs/16.1.6/full/abc123.tar.gz",
      bundle.package_key(checksum: "sha256:abc123")
    )
  end

  test "file_path rejects unsafe profile path traversal" do
    bundle = Bundle.new(
      version: versions(:nextjs_stable),
      profile: "../etc/passwd",
      format: "tar.gz"
    )

    assert_raises(ArgumentError) { bundle.file_path }
  end
end
