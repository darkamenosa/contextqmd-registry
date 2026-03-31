# frozen_string_literal: true

require "test_helper"

class Analytics::InternalPathsTest < ActiveSupport::TestCase
  test "report_internal_path? matches analytics-owned internal endpoints" do
    assert Analytics::InternalPaths.report_internal_path?("/analytics/events")
    assert Analytics::InternalPaths.report_internal_path?("/a/e")
    assert Analytics::InternalPaths.report_internal_path?("/ahoy/events")
    assert Analytics::InternalPaths.report_internal_path?("/assets/app.js")
    refute Analytics::InternalPaths.report_internal_path?("/about")
    refute Analytics::InternalPaths.report_internal_path?("/app/123/dashboard")
    refute Analytics::InternalPaths.report_internal_path?("/blog/how-plausible-works")
  end

  test "tracker and server prefix lists include analytics transport paths" do
    assert_includes Analytics::InternalPaths.tracker_exclude_prefixes, "/analytics"
    assert_includes Analytics::InternalPaths.tracker_exclude_prefixes, "/a"
    assert_includes Analytics::InternalPaths.server_excluded_prefixes, "/analytics"
    assert_includes Analytics::InternalPaths.server_excluded_prefixes, "/a"
    assert_includes Analytics::InternalPaths.server_excluded_prefixes, "/ahoy"
  end

  test "report_internal_sql_similar_pattern stays aligned with report prefixes" do
    pattern = Analytics::InternalPaths.report_internal_sql_similar_pattern

    assert_match %r{/analytics\\/%}, pattern
    assert_match %r{/a\\/%}, pattern
    assert_match %r{/ahoy\\/%}, pattern
    assert_match %r{\\/assets\\/%}, pattern
    refute_match %r{/about}, pattern
  end
end
