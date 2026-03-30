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

    assert_equal "https://analytics.example.test/js/script.js", payload.fetch(:script_url)
    assert_equal "https://analytics.example.test/ahoy/events", payload.fetch(:events_endpoint)
    assert_equal "docs.example.test", payload.fetch(:domain_hint)
    assert_includes payload.fetch(:snippet_html), %(data-site-token="#{payload.fetch(:site_token)}")
    assert_includes payload.fetch(:snippet_html), %(src="https://analytics.example.test/js/script.js")
  end
end
