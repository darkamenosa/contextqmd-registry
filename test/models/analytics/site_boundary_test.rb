# frozen_string_literal: true

require "test_helper"

class Analytics::SiteBoundaryTest < ActiveSupport::TestCase
  setup do
    Analytics::SiteBoundary.delete_all
    Analytics::Site.delete_all
  end

  test "site creation syncs a primary root boundary from canonical hostname" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "example.com")

    boundary = site.boundaries.find_by(primary: true)

    assert_not_nil boundary
    assert_equal "example.com", boundary.host
    assert_equal "/", boundary.path_prefix
  end

  test "resolve picks the longest matching path prefix on the same host" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "example.com")
    root_boundary = site.boundaries.find_by!(primary: true)
    docs_boundary = Analytics::SiteBoundary.create!(site: site, host: "example.com", path_prefix: "/docs")
    guides_boundary = Analytics::SiteBoundary.create!(site: site, host: "example.com", path_prefix: "/docs/guides")

    assert_equal root_boundary, Analytics::SiteBoundary.resolve(host: "example.com", path: "/")
    assert_equal docs_boundary, Analytics::SiteBoundary.resolve(host: "example.com", path: "/docs/search")
    assert_equal guides_boundary, Analytics::SiteBoundary.resolve(host: "example.com", path: "/docs/guides/ruby")
  end

  test "tracking site resolver returns the sole active site" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")

    resolution = Analytics::TrackingSiteResolver.resolve(host: "unmatched.example.test")

    assert_not_nil resolution
    assert_equal site, resolution.site
    assert_equal site.boundaries.find_by(primary: true), resolution.boundary
  end

  test "bootstrap creates the default site once and applies the provided name" do
    created = Analytics::Bootstrap.ensure_default_site!(host: "localhost:3000", name: "contextqmd.com")

    assert_not_nil created
    assert_equal "localhost", created.canonical_hostname
    assert_equal "contextqmd.com", created.name
    assert_equal "localhost", created.boundaries.find_by(primary: true)&.host
    assert_equal created, Analytics::Bootstrap.ensure_default_site!(host: "ignored.example.test", name: "contextqmd.com")
  end

  test "bootstrap updates singleton site name when an explicit name is provided again" do
    created = Analytics::Bootstrap.ensure_default_site!(host: "localhost:3000", name: "localhost")

    updated = Analytics::Bootstrap.ensure_default_site!(host: "localhost:3000", name: "contextqmd.com")

    assert_equal created, updated
    assert_equal "contextqmd.com", updated.reload.name
  end

  test "admin site selection is required when multiple sites are active" do
    Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    Analytics::Site.create!(name: "Blog", canonical_hostname: "blog.example.test")

    assert_equal true, Analytics::AdminSiteResolver.selection_required?
    assert_equal false, Analytics::AdminSiteResolver.selection_required?(explicit_site_id: "docs.example.test")
  end

  test "admin site resolver returns nil without explicit selection in multi-site mode" do
    Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    Analytics::Site.create!(name: "Blog", canonical_hostname: "blog.example.test")

    assert_nil Analytics::AdminSiteResolver.resolve
  end

  test "admin site resolver can use a unique host match in multi-site mode" do
    local = Analytics::Site.create!(name: "Local", canonical_hostname: "localhost")
    Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")

    resolution = Analytics::AdminSiteResolver.resolve(request: Struct.new(:host).new("localhost"))

    assert_not_nil resolution
    assert_equal local, resolution.site
  end

  test "admin site resolver only resolves active explicit sites" do
    site = Analytics::Site.create!(
      name: "Docs",
      canonical_hostname: "docs.example.test",
      status: Analytics::Site::STATUS_ARCHIVED
    )

    assert_raises(ActiveRecord::RecordNotFound) do
      Analytics::AdminSiteResolver.resolve!(explicit_site_id: site.public_id)
    end
  end

  test "resolve prefers the longest matching prefix before priority" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "example.com")
    Analytics::SiteBoundary.create!(site: site, host: "example.com", path_prefix: "/docs", priority: 10)
    api_boundary = Analytics::SiteBoundary.create!(site: site, host: "example.com", path_prefix: "/docs/api", priority: 0)

    assert_equal api_boundary, Analytics::SiteBoundary.resolve(host: "example.com", path: "/docs/api/v1")
  end

  test "normalize_path_prefix handles full URLs and trailing slashes" do
    assert_equal "/docs", Analytics::SiteBoundary.normalize_path_prefix("https://example.com/docs/")
    assert_equal "/docs", Analytics::SiteBoundary.normalize_path_prefix("docs/")
    assert_equal "/", Analytics::SiteBoundary.normalize_path_prefix(nil)
  end
end
