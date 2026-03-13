# frozen_string_literal: true

require "test_helper"

class BuildBundleJobTest < ActiveSupport::TestCase
  setup do
    _identity, account, _user = create_tenant(
      email: "build-bundle-#{SecureRandom.hex(4)}@example.com",
      name: "Build Bundle Test"
    )

    @library = Library.create!(
      account: account,
      namespace: "build-bundle-#{SecureRandom.hex(4)}",
      name: "library-#{SecureRandom.hex(4)}",
      display_name: "Build Bundle Library",
      homepage_url: "https://example.com/docs"
    )
    @version = @library.versions.create!(
      version: "1.0.0",
      channel: "stable",
      generated_at: Time.current,
      manifest_checksum: "sha256:#{SecureRandom.hex(32)}"
    )
    @version.pages.create!(
      page_uid: "readme",
      path: "README.md",
      title: "Readme",
      url: "https://example.com/readme",
      description: "# Readme\n\nBundle me.",
      bytes: 20,
      checksum: Digest::SHA256.hexdigest("# Readme\n\nBundle me."),
      headings: [ "Readme" ]
    )
  end

  teardown do
    FileUtils.rm_rf(DocsBundle.storage_root)
  end

  test "builds a pending bundle and marks it ready" do
    bundle = @version.bundles.create!(profile: "full", status: "pending")

    BuildBundleJob.perform_now(bundle)

    bundle.reload
    assert_equal "ready", bundle.status
    assert_equal "tar.gz", bundle.format
    assert_match(/\Asha256:[0-9a-f]{64}\z/, bundle.sha256)
    assert_operator bundle.size_bytes, :positive?
    assert_nil bundle.error_message
    assert bundle.package.attached?, "Expected bundle package to be attached after publish"
    assert_equal "test", bundle.package.blob.service_name
    assert File.exist?(bundle.file_path), "Expected bundle file to exist after job completes"
  end

  test "marks the bundle failed when bundle generation raises" do
    bundle = @version.bundles.create!(profile: "full", status: "pending")

    original_refresh = DocsBundle.method(:refresh!)
    DocsBundle.define_singleton_method(:refresh!) { |_version, profile:| raise "bundle explosion" }

    begin
      assert_raises(RuntimeError) do
        BuildBundleJob.perform_now(bundle)
      end
    ensure
      DocsBundle.define_singleton_method(:refresh!, original_refresh)
    end

    bundle.reload
    assert_equal "failed", bundle.status
    assert_equal "bundle explosion", bundle.error_message
  end
end
