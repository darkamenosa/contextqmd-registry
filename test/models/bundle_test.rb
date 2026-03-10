# frozen_string_literal: true

require "test_helper"

class BundleTest < ActiveSupport::TestCase
  fixtures :accounts, :libraries, :versions, :bundles

  test "valid bundle" do
    bundle = Bundle.new(
      version: versions(:nextjs_stable),
      profile: "compact",
      format: "tar.zst",
      sha256: "sha256:abc123def456"
    )
    assert bundle.valid?
  end

  test "requires profile" do
    bundle = Bundle.new(version: versions(:nextjs_stable), format: "tar.zst", sha256: "sha256:abc")
    assert_not bundle.valid?
    assert bundle.errors[:profile].present?
  end

  test "requires format" do
    bundle = Bundle.new(version: versions(:nextjs_stable), profile: "full", sha256: "sha256:abc")
    assert_not bundle.valid?
    assert bundle.errors[:format].present?
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
end
