# frozen_string_literal: true

require "test_helper"

class AnalyticsProfileProjectionTest < ActiveSupport::TestCase
  setup do
    Ahoy::Event.delete_all
    Ahoy::Visit.delete_all
    AnalyticsProfileSession.delete_all if defined?(AnalyticsProfileSession)
    AnalyticsProfileSummary.delete_all if defined?(AnalyticsProfileSummary)
    AnalyticsProfileKey.delete_all
    AnalyticsProfile.delete_all
    Analytics::SiteBoundary.delete_all
    Analytics::Site.delete_all
  end

  test "project_visit retries when the session row is inserted concurrently" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    profile = AnalyticsProfile.create!(
      analytics_site: site,
      status: AnalyticsProfile::STATUS_ANONYMOUS,
      first_seen_at: 10.minutes.ago,
      last_seen_at: 1.minute.ago
    )

    visit = Ahoy::Visit.create!(
      analytics_site: site,
      analytics_profile: profile,
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      browser_id: SecureRandom.uuid,
      started_at: 5.minutes.ago.change(usec: 0),
      country: "Spain",
      city: "Barcelona",
      device_type: "Desktop",
      browser: "Chrome",
      os: "Mac OS",
      landing_page: "https://docs.example.test/pricing"
    )

    Ahoy::Event.create!(
      analytics_site: site,
      visit: visit,
      name: "pageview",
      properties: { page: "/pricing" },
      time: 4.minutes.ago.change(usec: 0)
    )

    original_finder = AnalyticsProfileSession.method(:find_or_initialize_by)
    injected = AnalyticsProfileSession.new(visit_id: visit.id)
    first_attempt = true

    injected.define_singleton_method(:save!) do
      if first_attempt
        first_attempt = false

        AnalyticsProfileSession.create!(
          visit: visit,
          analytics_profile: profile,
          analytics_site: site,
          started_at: visit.started_at,
          last_event_at: visit.started_at,
          device_type: "Desktop",
          source: "Direct / None",
          duration_seconds: 0,
          pageviews_count: 0,
          events_count: 0,
          page_paths: [],
          event_names: []
        )

        raise ActiveRecord::RecordNotUnique, "duplicate analytics profile session"
      end

      super()
    end

    analytics_profile_session_singleton = class << AnalyticsProfileSession; self; end
    analytics_profile_session_singleton.alias_method :__projection_test_original_find_or_initialize_by, :find_or_initialize_by
    analytics_profile_session_singleton.define_method(:find_or_initialize_by) do |**attrs|
      first_attempt ? injected : original_finder.call(**attrs)
    end

    begin
      AnalyticsProfile::Projection.project_visit(visit)
    ensure
      analytics_profile_session_singleton.alias_method :find_or_initialize_by, :__projection_test_original_find_or_initialize_by
      analytics_profile_session_singleton.remove_method :__projection_test_original_find_or_initialize_by
    end

    session = AnalyticsProfileSession.find_by!(visit_id: visit.id)
    assert_equal profile.id, session.analytics_profile_id
    assert_equal site.id, session.analytics_site_id
    assert_equal "/pricing", session.entry_page
    assert_equal "/pricing", session.current_page
    assert_equal 1, session.pageviews_count
    assert_equal [ "/pricing" ], session.page_paths
    assert_equal [ "pageview" ], session.event_names
  end
end
