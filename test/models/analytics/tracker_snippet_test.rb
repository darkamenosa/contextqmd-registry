# frozen_string_literal: true

require "test_helper"

class Analytics::TrackerSnippetTest < ActiveSupport::TestCase
  setup do
    Analytics::SiteBoundary.delete_all
    Analytics::Site.delete_all
  end

  test "build returns a copy-paste snippet for the current analytics service origin" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    request = Struct.new(:base_url).new("https://analytics.example.test")

    payload = Analytics::TrackerSnippet.build(site: site, request: request)

    assert_equal "https://analytics.example.test/analytics/script.js", payload.fetch(:script_url)
    assert_equal site.public_id, payload.fetch(:website_id)
    assert_equal "docs.example.test", payload.fetch(:domain_hint)
    assert_includes payload.fetch(:snippet_html), %(data-website-id="#{site.public_id}")
    assert_includes payload.fetch(:snippet_html), %(src="https://analytics.example.test/analytics/script.js")
    refute_includes payload.fetch(:snippet_html), "data-domain="
  end
end
