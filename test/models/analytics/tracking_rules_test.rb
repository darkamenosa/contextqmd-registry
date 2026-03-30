# frozen_string_literal: true

require "test_helper"

class Analytics::TrackingRulesTest < ActiveSupport::TestCase
  setup do
    Analytics::Setting.delete_all
    Analytics::Site.delete_all
  end

  test "load normalizes site-scoped tracking rules" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    Analytics::TrackingRules.save!(
      include_paths: [ "blog/**", "/docs/**", "blog/**" ],
      exclude_paths: [ "preview/**", "/internal/**" ],
      site: site
    )

    rules = Analytics::TrackingRules.load(site: site)
    effective = Analytics::TrackingRules.effective(site: site)

    assert_equal [ "/blog/**", "/docs/**" ], rules.include_paths
    assert_equal [ "/preview/**", "/internal/**" ], rules.exclude_paths
    assert_includes effective.exclude_paths, "/analytics"
    assert_includes effective.exclude_paths, "/preview/**"
  end

  test "trackable_path? applies include and exclude rules with wildcard matching" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    Analytics::TrackingRules.save!(
      include_paths: [ "/docs/**" ],
      exclude_paths: [ "/docs/private/**" ],
      site: site
    )

    assert Analytics::TrackingRules.trackable_path?("/docs/intro", site: site, include_internal_defaults: false)
    refute Analytics::TrackingRules.trackable_path?("/pricing", site: site, include_internal_defaults: false)
    refute Analytics::TrackingRules.trackable_path?("/docs/private/plan", site: site, include_internal_defaults: false)
  end
end
