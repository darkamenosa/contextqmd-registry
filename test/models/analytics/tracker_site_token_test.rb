# frozen_string_literal: true

require "test_helper"

class Analytics::TrackerSiteTokenTest < ActiveSupport::TestCase
  setup do
    Analytics::SiteBoundary.delete_all
    Analytics::Site.delete_all
  end

  test "generates a signed token constrained to the resolved boundary" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "example.com")
    Analytics::SiteBoundary.create!(site: site, host: "example.com", path_prefix: "/blog")

    token = Analytics::TrackerSiteToken.generate(
      site: site,
      host: "example.com",
      path: "/blog/post-1"
    )

    resolution = Analytics::TrackerSiteToken.verify(
      token,
      host: "example.com",
      path: "/blog/post-1"
    )

    assert_not_nil resolution
    assert_equal site, resolution.site
    assert_equal(
      [
        { "host" => "example.com", "path_prefix" => "/" },
        { "host" => "example.com", "path_prefix" => "/blog" }
      ],
      resolution.claims.fetch("allowed_boundaries")
    )
    assert_equal "example.com", resolution.claims.fetch("allowed_hosts").first
    assert_includes resolution.claims.fetch("allowed_path_prefixes"), "/blog"
  end

  test "rejects tokens on a different host or path" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "example.com")
    Analytics::SiteBoundary.create!(site: site, host: "docs.example.com", path_prefix: "/blog")

    token = Analytics::TrackerSiteToken.generate(
      site: site,
      host: "example.com",
      path: "/blog/post-1"
    )

    assert_nil Analytics::TrackerSiteToken.verify(token, host: "other.example.com", path: "/")
    assert_nil Analytics::TrackerSiteToken.verify(token, host: "docs.example.com", path: "/docs")
  end

  test "rejects a mixed host and path combination that is not an allowed boundary pair" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "example.com")
    Analytics::SiteBoundary.create!(site: site, host: "example.com", path_prefix: "/blog")
    Analytics::SiteBoundary.create!(site: site, host: "docs.example.com", path_prefix: "/docs")

    token = Analytics::TrackerSiteToken.generate(site: site)

    assert_nil Analytics::TrackerSiteToken.verify(
      token,
      host: "docs.example.com",
      path: "/blog/post-1"
    )
  end
end
