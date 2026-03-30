# frozen_string_literal: true

require "test_helper"

class Analytics::TrackerBootstrapTest < ActiveSupport::TestCase
  setup do
    Analytics::SiteBoundary.delete_all
    Analytics::Site.delete_all
  end

  test "build returns unified bootstrap payload with signed token for resolved site" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    request = Struct.new(:host, :path, :original_url).new(
      "docs.example.test",
      "/",
      "https://docs.example.test/"
    )

    payload = Analytics::TrackerBootstrap.build(
      request: request,
      initial_pageview_tracked: true,
      initial_page_key: "/"
    )

    assert_equal 1, payload.fetch(:version)
    assert_equal "/ahoy/events", payload.dig(:transport, :eventsEndpoint)
    assert_equal true, payload.dig(:tracking, :initialPageviewTracked)
    assert_equal "/", payload.dig(:tracking, :initialPageKey)
    assert_not_nil payload.dig(:site, :token)
    assert_equal site.canonical_hostname, payload.dig(:site, :domainHint)
  end
end
