# frozen_string_literal: true

require "test_helper"

class Analytics::LiveStateTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  setup do
    Ahoy::Event.delete_all
    Ahoy::Visit.delete_all
  end

  test "yesterday session comparison excludes today's midnight boundary" do
    travel_to Time.utc(2026, 3, 24, 10, 0, 0) do
      Time.use_zone("UTC") do
        Ahoy::Visit.create!(
          visit_token: SecureRandom.hex(16),
          visitor_token: SecureRandom.hex(16),
          started_at: Time.zone.parse("2026-03-23 00:00:00")
        )
        Ahoy::Visit.create!(
          visit_token: SecureRandom.hex(16),
          visitor_token: SecureRandom.hex(16),
          started_at: Time.zone.parse("2026-03-24 00:00:00")
        )

        stats = Analytics::LiveState.build(now: Time.zone.parse("2026-03-24 10:00:00"), camelize: false)

        assert_equal 1, stats.dig(:today_sessions, :count)
        assert_equal 0, stats.dig(:today_sessions, :change)
      end
    end
  end

  test "recent live activity keeps recently ended sessions after active presence drops" do
    travel_to Time.utc(2026, 3, 28, 10, 0, 0) do
      Time.use_zone("UTC") do
        active_profile = AnalyticsProfile.create!(
          status: AnalyticsProfile::STATUS_ANONYMOUS,
          first_seen_at: 20.minutes.ago,
          last_seen_at: 1.minute.ago
        )
        inactive_profile = AnalyticsProfile.create!(
          status: AnalyticsProfile::STATUS_ANONYMOUS,
          first_seen_at: 30.minutes.ago,
          last_seen_at: 8.minutes.ago
        )

        active_visit = Ahoy::Visit.create!(
          visit_token: SecureRandom.hex(16),
          visitor_token: SecureRandom.hex(16),
          analytics_profile: active_profile,
          started_at: 10.minutes.ago,
          latitude: 10.0,
          longitude: 10.0
        )
        inactive_visit = Ahoy::Visit.create!(
          visit_token: SecureRandom.hex(16),
          visitor_token: SecureRandom.hex(16),
          analytics_profile: inactive_profile,
          started_at: 20.minutes.ago,
          latitude: 20.0,
          longitude: 20.0
        )

        Ahoy::Event.create!(
          visit: active_visit,
          name: "pageview",
          properties: { page: "/active" },
          time: 1.minute.ago
        )
        Ahoy::Event.create!(
          visit: inactive_visit,
          name: "pageview",
          properties: { page: "/inactive" },
          time: 6.minutes.ago
        )

        stats = Analytics::LiveState.build(now: Time.zone.parse("2026-03-28 10:00:00"), camelize: false)

        assert_equal 1, stats.fetch(:current_visitors)
        assert_equal [ active_visit.id.to_s ], stats.fetch(:live_sessions).map { |session| session.fetch(:id) }
        assert_equal [ "/active", "/inactive" ], stats.fetch(:recent_events).map { |event| event.fetch(:page) }
        assert_equal [ true, false ], stats.fetch(:recent_events).map { |event| event.fetch(:active) }
        assert_equal [ "/active" ], stats.fetch(:live_sessions).flat_map { |session| session.fetch(:recent_events).map { |event| event.fetch(:page) } }
      end
    end
  end

  test "live sessions are visit based even when the profile is shared" do
    travel_to Time.utc(2026, 3, 28, 10, 0, 0) do
      Time.use_zone("UTC") do
        profile = AnalyticsProfile.create!(
          status: AnalyticsProfile::STATUS_IDENTIFIED,
          traits: {
            display_name: "Coral Wildcat",
            email: "coral@example.com"
          },
          first_seen_at: 1.day.ago,
          last_seen_at: 1.minute.ago
        )

        first_visit = Ahoy::Visit.create!(
          visit_token: SecureRandom.hex(16),
          visitor_token: SecureRandom.hex(16),
          analytics_profile: profile,
          started_at: 4.minutes.ago,
          latitude: 10.0,
          longitude: 10.0,
          landing_page: "https://example.test/libraries"
        )
        second_visit = Ahoy::Visit.create!(
          visit_token: SecureRandom.hex(16),
          visitor_token: SecureRandom.hex(16),
          analytics_profile: profile,
          started_at: 3.minutes.ago,
          latitude: 11.0,
          longitude: 11.0,
          landing_page: "https://example.test/app/2/dashboard"
        )

        Ahoy::Event.create!(
          visit: first_visit,
          name: "pageview",
          properties: { page: "/libraries" },
          time: 45.seconds.ago
        )
        Ahoy::Event.create!(
          visit: second_visit,
          name: "pageview",
          properties: { page: "/app/2/dashboard" },
          time: 30.seconds.ago
        )

        stats = Analytics::LiveState.build(now: Time.zone.parse("2026-03-28 10:00:00"), camelize: false)

        assert_equal 2, stats.fetch(:current_visitors)
        assert_equal [ first_visit.id, second_visit.id ].sort, stats.fetch(:live_sessions).map { |session| session.fetch(:visit_id) }.sort
        assert_equal [ "/libraries", "/app/2/dashboard" ].sort, stats.fetch(:live_sessions).map { |session| session.fetch(:current_page) }.sort
      end
    end
  end

  test "current_visitors delegates through the live-state boundary" do
    travel_to Time.utc(2026, 3, 28, 10, 0, 0) do
      Time.use_zone("UTC") do
        visit = Ahoy::Visit.create!(
          visit_token: SecureRandom.hex(16),
          visitor_token: SecureRandom.hex(16),
          started_at: 10.minutes.ago
        )

        Ahoy::Event.create!(
          visit: visit,
          name: "pageview",
          properties: { page: "/active" },
          time: 30.seconds.ago
        )

        assert_equal 1, Analytics::LiveState.current_visitors(now: Time.zone.parse("2026-03-28 10:00:00"))
      end
    end
  end

  test "broadcast_now uses the scoped analytics stream and payload" do
    travel_to Time.utc(2026, 3, 28, 10, 0, 0) do
      Time.use_zone("UTC") do
        site_a = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test", time_zone: "UTC")
        site_b = Analytics::Site.create!(name: "Blog", canonical_hostname: "blog.example.test", time_zone: "UTC")

        profile_a = AnalyticsProfile.create!(
          analytics_site: site_a,
          status: AnalyticsProfile::STATUS_ANONYMOUS,
          first_seen_at: 20.minutes.ago,
          last_seen_at: 1.minute.ago
        )
        profile_b = AnalyticsProfile.create!(
          analytics_site: site_b,
          status: AnalyticsProfile::STATUS_ANONYMOUS,
          first_seen_at: 20.minutes.ago,
          last_seen_at: 1.minute.ago
        )

        visit_a = Ahoy::Visit.create!(
          analytics_site: site_a,
          analytics_profile: profile_a,
          visit_token: SecureRandom.hex(16),
          visitor_token: SecureRandom.hex(16),
          started_at: 4.minutes.ago,
          latitude: 10.0,
          longitude: 10.0
        )
        visit_b = Ahoy::Visit.create!(
          analytics_site: site_b,
          analytics_profile: profile_b,
          visit_token: SecureRandom.hex(16),
          visitor_token: SecureRandom.hex(16),
          started_at: 4.minutes.ago,
          latitude: 20.0,
          longitude: 20.0
        )

        Ahoy::Event.create!(
          analytics_site: site_a,
          visit: visit_a,
          name: "pageview",
          properties: { page: "/docs" },
          time: 30.seconds.ago
        )
        Ahoy::Event.create!(
          analytics_site: site_b,
          visit: visit_b,
          name: "pageview",
          properties: { page: "/blog" },
          time: 30.seconds.ago
        )

        broadcasts = []

        server = ActionCable.server
        original_broadcast = server.method(:broadcast)

        server.define_singleton_method(:broadcast) do |stream, payload|
          broadcasts << [ stream, payload ]
        end

        begin
          Analytics::LiveState.broadcast_now(
            now: Time.zone.parse("2026-03-28 10:00:00"),
            site: site_a
          )
        ensure
          server.define_singleton_method(:broadcast, original_broadcast)
        end

        assert_equal 1, broadcasts.size
        stream, payload = broadcasts.first

        assert_equal "analytics:#{site_a.public_id}", stream
        assert_equal 1, payload.fetch("currentVisitors")
        assert_equal [ "/docs" ], payload.fetch("recentEvents").map { |event| event.fetch("page") }
      end
    end
  end

  test "live subscription tokens resolve back to the scoped analytics stream" do
    site = Analytics::Site.create!(
      name: "Docs",
      canonical_hostname: "docs.example.test",
      time_zone: "UTC"
    )

    token = Analytics::LiveState.subscription_token(site: site)

    assert_equal(
      "analytics:#{site.public_id}",
      Analytics::LiveState.resolve_subscription_stream(token)
    )
  end

  test "live subscription stream resolution rejects invalid tokens" do
    assert_nil Analytics::LiveState.resolve_subscription_stream("invalid-token")
  end

  test "live broadcast job resolves the scoped site before broadcasting" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test", time_zone: "UTC")
    captured_site = :unset

    original_broadcast_now = Analytics::LiveState.method(:broadcast_now)

    Analytics::LiveState.define_singleton_method(:broadcast_now) do |site: nil, **|
      captured_site = site
    end

    begin
      Analytics::LiveBroadcastJob.perform_now(site.public_id)
    ensure
      Analytics::LiveState.define_singleton_method(:broadcast_now, original_broadcast_now)
    end

    assert_equal site, captured_site
  end

  test "visitor dots expose a non-city location label when coordinates are present" do
    travel_to Time.utc(2026, 3, 28, 10, 0, 0) do
      Time.use_zone("UTC") do
        visit = Ahoy::Visit.create!(
          visit_token: SecureRandom.hex(16),
          visitor_token: SecureRandom.hex(16),
          started_at: 2.minutes.ago,
          latitude: 48.8566,
          longitude: 2.3522,
          city: nil,
          region: nil,
          country: "France"
        )

        Ahoy::Event.create!(
          visit: visit,
          name: "pageview",
          properties: { page: "/pricing" },
          time: 30.seconds.ago
        )

        stats = Analytics::LiveState.build(now: Time.zone.parse("2026-03-28 10:00:00"), camelize: false)

        assert_equal "France", stats.fetch(:visitor_dots).first.fetch(:label)
      end
    end
  end

  test "visitor dots combine city and country in their canonical label" do
    travel_to Time.utc(2026, 3, 28, 10, 0, 0) do
      Time.use_zone("UTC") do
        visit = Ahoy::Visit.create!(
          visit_token: SecureRandom.hex(16),
          visitor_token: SecureRandom.hex(16),
          started_at: 2.minutes.ago,
          latitude: 41.3874,
          longitude: 2.1686,
          city: "Barcelona",
          region: nil,
          country: "Spain"
        )

        Ahoy::Event.create!(
          visit: visit,
          name: "pageview",
          properties: { page: "/pricing" },
          time: 30.seconds.ago
        )

        stats = Analytics::LiveState.build(now: Time.zone.parse("2026-03-28 10:00:00"), camelize: false)

        assert_equal "Barcelona, Spain", stats.fetch(:visitor_dots).first.fetch(:label)
        assert_equal "ES", stats.fetch(:visitor_dots).first.fetch(:country_code)
      end
    end
  end
end
