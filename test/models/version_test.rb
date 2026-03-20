# frozen_string_literal: true

require "test_helper"

class VersionTest < ActiveSupport::TestCase
  fixtures :accounts, :libraries, :versions

  test "valid version" do
    version = Version.new(
      library: libraries(:nextjs),
      version: "17.0.0",
      channel: "stable",
      generated_at: Time.current
    )
    assert version.valid?
  end

  test "requires version" do
    version = Version.new(library: libraries(:nextjs), channel: "stable")
    assert_not version.valid?
    assert version.errors[:version].present?
  end

  test "requires valid channel" do
    version = Version.new(library: libraries(:nextjs), version: "17.0.0", channel: "nightly")
    assert_not version.valid?
    assert version.errors[:channel].present?
  end

  test "channel must be one of stable, latest, canary, snapshot" do
    %w[stable latest canary snapshot].each do |ch|
      version = Version.new(library: libraries(:nextjs), version: "17.0.0-#{ch}", channel: ch)
      assert version.valid?, "Expected channel '#{ch}' to be valid"
    end
  end

  test "version is unique per library" do
    # nextjs_stable fixture already exists with version: "16.1.6"
    duplicate = Version.new(
      library: libraries(:nextjs),
      version: "16.1.6",
      channel: "stable"
    )
    assert_not duplicate.valid?
    assert duplicate.errors[:version].present?
  end

  test "same version string allowed on different libraries" do
    version = Version.new(
      library: libraries(:rails),
      version: "16.1.6",
      channel: "stable"
    )
    assert version.valid?
  end

  test "ordered scope sorts by generated_at desc" do
    versions = Version.ordered
    generated_dates = versions.map(&:generated_at).compact
    assert_equal generated_dates.sort.reverse, generated_dates
  end

  test "stable scope filters stable channel" do
    stable_versions = Version.stable
    assert stable_versions.all? { |v| v.channel == "stable" }
  end

  test "belongs to library" do
    version = versions(:nextjs_stable)
    assert_equal libraries(:nextjs), version.library
  end

  test "query_docs returns matching chunks" do
    version = libraries(:rails).versions.create!(
      version: "query-docs-#{SecureRandom.hex(4)}",
      channel: "stable",
      generated_at: Time.current
    )

    version.pages.create!(
      page_uid: "installing",
      path: "installing.md",
      title: "Installing",
      description: "Install the library and configure the adapter for local development.",
      bytes: 80,
      headings: [ "Install", "Configure" ]
    )

    results = version.query_docs(query: "install configure", max_tokens: 50_000)

    assert_equal 1, results[:total_matches]
    assert_equal "installing", results[:results].first[:page_uid]
  end

  test "query_docs fast mode returns whole page content" do
    version = libraries(:rails).versions.create!(
      version: "query-fast-#{SecureRandom.hex(4)}",
      channel: "stable",
      generated_at: Time.current
    )

    version.pages.create!(
      page_uid: "reference",
      path: "reference.md",
      title: "Reference",
      description: "Full API reference for the library.",
      bytes: 40,
      headings: [ "API" ]
    )

    results = version.query_docs(query: "reference", max_tokens: 50_000, mode: :fast)

    assert_equal "Full API reference for the library.", results[:results].first[:content_md]
  end
end
