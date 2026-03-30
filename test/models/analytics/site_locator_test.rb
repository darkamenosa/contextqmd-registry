# frozen_string_literal: true

require "test_helper"

class Analytics::SiteLocatorTest < ActiveSupport::TestCase
  setup do
    Analytics::SiteBoundary.delete_all
    Analytics::Site.delete_all
  end

  test "returns the loaded analytics site from a record" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    record = Struct.new(:analytics_site, :analytics_site_id).new(site, nil)

    assert_equal site, Analytics::SiteLocator.from_record(record)
  end

  test "resolves a site from an analytics record with only analytics_site_id" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    record = Struct.new(:analytics_site, :analytics_site_id).new(nil, site.id)

    assert_equal site, Analytics::SiteLocator.from_record(record)
  end

  test "resolves a site from a public id" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")

    assert_equal site, Analytics::SiteLocator.from_public_id(site.public_id)
  end
end
