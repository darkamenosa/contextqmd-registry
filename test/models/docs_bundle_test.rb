# frozen_string_literal: true

require "test_helper"
require "rubygems/package"
require "zlib"

class DocsBundleTest < ActiveSupport::TestCase
  setup do
    _identity, account, _user = create_tenant(
      email: "docs-bundle-#{SecureRandom.hex(4)}@example.com",
      name: "Docs Bundle Test"
    )
    @library = Library.create!(
      account: account,
      namespace: "docs-bundle-#{SecureRandom.hex(4)}",
      name: "library-#{SecureRandom.hex(4)}",
      display_name: "Docs Bundle Library",
      homepage_url: "https://example.com/docs"
    )
    @library.create_source_policy!(
      license_name: "MIT",
      license_status: "verified",
      mirror_allowed: true,
      origin_fetch_allowed: true,
      attribution_required: false
    )
    @version = @library.versions.create!(
      version: "1.0.0",
      channel: "stable",
      generated_at: Time.utc(2026, 3, 12, 8, 0, 0),
      manifest_checksum: "sha256:#{SecureRandom.hex(32)}"
    )
    @version.create_fetch_recipe!(
      source_type: "llms_txt",
      url: "https://example.com/llms.txt",
      normalizer_version: "1.0",
      splitter_version: "1.0"
    )

    create_page(
      page_uid: "getting-started",
      path: "guides/getting-started.md",
      title: "Getting Started",
      content: "# Getting Started\n\nInstall it."
    )
    create_page(
      page_uid: "api-reference",
      path: "reference/api.md",
      title: "API Reference",
      content: "# API Reference\n\nCall the API."
    )
  end

  teardown do
    FileUtils.rm_rf(DocsBundle.storage_root)
  end

  test "refresh! writes a deterministic bundle with manifest index and pages" do
    bundle = DocsBundle.refresh!(@version, profile: "full")

    assert_equal "full", bundle.profile
    assert_equal "tar.gz", bundle.format
    assert bundle.package.attached?, "Expected bundle package to be attached"
    assert_equal "test", bundle.package.blob.service_name
    assert_equal(
      "bundles/public/#{@library.slug}/#{@version.version}/full/#{bundle.sha256.delete_prefix("sha256:")}.tar.gz",
      bundle.package.blob.key
    )
    assert File.exist?(bundle.file_path), "Expected bundle file to exist"

    entries = bundle_entries(bundle.file_path)

    assert_equal(
      [
        "manifest.json",
        "page-index.json",
        "pages/#{Digest::SHA256.hexdigest("api-reference")}.md",
        "pages/#{Digest::SHA256.hexdigest("getting-started")}.md"
      ].sort,
      entries.keys.sort
    )

    manifest = JSON.parse(entries.fetch("manifest.json"))
    assert_equal @library.display_name, manifest["display_name"]
    assert_equal @library.slug, manifest["slug"]
    assert_equal @version.version, manifest["version"]
    assert_equal 2, manifest["doc_count"]
    assert_equal "page-index.json", manifest.dig("page_index", "path")

    page_index = JSON.parse(entries.fetch("page-index.json"))
    assert_equal [ "api-reference", "getting-started" ], page_index.map { |page| page.fetch("page_uid") }
    getting_started = page_index.find { |page| page.fetch("page_uid") == "getting-started" }
    api_reference = page_index.find { |page| page.fetch("page_uid") == "api-reference" }
    assert_equal "# Getting Started\n\nInstall it.", entries.fetch("pages/#{getting_started.fetch("bundle_path")}")
    assert_equal "# API Reference\n\nCall the API.", entries.fetch("pages/#{api_reference.fetch("bundle_path")}")
  end

  test "refresh! produces identical bytes for unchanged content" do
    first_bundle = DocsBundle.refresh!(@version, profile: "full")
    first_bytes = File.binread(first_bundle.file_path)
    first_key = first_bundle.package.blob.key

    second_bundle = DocsBundle.refresh!(@version, profile: "full")
    second_bytes = File.binread(second_bundle.file_path)

    assert_equal first_bytes, second_bytes
    assert_equal first_bundle.sha256, second_bundle.sha256
    assert_equal first_bundle.size_bytes, second_bundle.size_bytes
    assert_equal first_key, second_bundle.package.blob.key
  end

  test "refresh! uses a new package key when republish changes bundle bytes" do
    first_bundle = DocsBundle.refresh!(@version, profile: "full")
    first_key = first_bundle.package.blob.key

    page = @version.pages.find_by!(page_uid: "getting-started")
    updated_content = "# Getting Started\n\nInstall it faster."
    page.update!(
      description: updated_content,
      bytes: updated_content.bytesize,
      checksum: Digest::SHA256.hexdigest(updated_content)
    )

    second_bundle = DocsBundle.refresh!(@version, profile: "full")

    assert_not_equal first_bundle.sha256, second_bundle.sha256
    assert_not_equal first_key, second_bundle.package.blob.key
    assert_equal(
      "bundles/public/#{@library.slug}/#{@version.version}/full/#{second_bundle.sha256.delete_prefix("sha256:")}.tar.gz",
      second_bundle.package.blob.key
    )
  end

  test "refresh! supports long page_uids by storing bundle_path separately" do
    create_page(
      page_uid: "turbopack/crates/turbopack/tests/tests/execution/turbopack/async-modules/top-level-await/input/readme",
      path: "guides/turbopack-readme.md",
      title: "Turbopack Readme",
      content: "# Turbopack\n\nLong page UID."
    )

    bundle = DocsBundle.refresh!(@version, profile: "full")
    entries = bundle_entries(bundle.file_path)
    page_index = JSON.parse(entries.fetch("page-index.json"))
    long_page = page_index.find { |page| page.fetch("page_uid").include?("turbopack/async-modules") }

    assert_not_nil long_page
    assert_match(/\A[0-9a-f]{64}\.md\z/, long_page.fetch("bundle_path"))
    assert_equal "# Turbopack\n\nLong page UID.", entries.fetch("pages/#{long_page.fetch("bundle_path")}")
  end

  private

    def create_page(page_uid:, path:, title:, content:)
      @version.pages.create!(
        page_uid: page_uid,
        path: path,
        title: title,
        url: "https://example.com/#{page_uid}",
        description: content,
        bytes: content.bytesize,
        checksum: Digest::SHA256.hexdigest(content),
        headings: [ title ]
      )
    end

    def bundle_entries(path)
      entries = {}

      Zlib::GzipReader.open(path) do |gzip|
        Gem::Package::TarReader.new(gzip) do |tar|
          tar.each do |entry|
            next unless entry.file?

            entries[entry.full_name] = entry.read
          end
        end
      end

      entries
    end
end
