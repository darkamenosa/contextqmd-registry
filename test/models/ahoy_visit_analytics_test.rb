# frozen_string_literal: true

require "test_helper"
require "ostruct"

class AhoyVisitAnalyticsTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  include ActiveSupport::Testing::TimeHelpers

  setup do
    Ahoy::Event.delete_all
    Ahoy::Visit.delete_all
    AnalyticsProfileSession.delete_all if defined?(AnalyticsProfileSession)
    AnalyticsProfileSummary.delete_all if defined?(AnalyticsProfileSummary)
    AnalyticsProfileKey.delete_all if defined?(AnalyticsProfileKey)
    AnalyticsProfile.delete_all if defined?(AnalyticsProfile)
    Analytics::GoogleSearchConsole::QueryRow.delete_all
    Analytics::GoogleSearchConsole::Sync.delete_all
    Analytics::GoogleSearchConsoleConnection.delete_all
    Analytics::AllowedEventProperty.delete_all if defined?(Analytics::AllowedEventProperty)
    Analytics::Goal.delete_all
    Analytics::Funnel.delete_all
    Analytics::SiteBoundary.delete_all
    Analytics::Site.delete_all
    clear_enqueued_jobs
    clear_performed_jobs
  end

  test "resolve_profile_later coalesces duplicate jobs for the same visit and identity inputs" do
    visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      browser_id: SecureRandom.uuid,
      started_at: Time.zone.now.change(usec: 0)
    )

    assert_enqueued_jobs 1, only: Analytics::ProfileResolutionJob do
      2.times do
        visit.resolve_profile_later(
          browser_id: visit.browser_id,
          strong_keys: {},
          occurred_at: Time.current
        )
      end
    end
  end

  test "resolve_profile_later enqueues again when identity inputs change" do
    visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      browser_id: SecureRandom.uuid,
      started_at: Time.zone.now.change(usec: 0)
    )

    assert_enqueued_jobs 2, only: Analytics::ProfileResolutionJob do
      visit.resolve_profile_later(
        browser_id: visit.browser_id,
        strong_keys: {},
        occurred_at: Time.current
      )
      visit.resolve_profile_later(
        browser_id: visit.browser_id,
        strong_keys: { identity_id: 123 },
        occurred_at: Time.current
      )
    end
  end

  test "project_later coalesces duplicate jobs for the same visit projection inputs" do
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
      started_at: 5.minutes.ago.change(usec: 0)
    )

    assert_enqueued_jobs 1, only: Analytics::VisitProjectionJob do
      2.times { visit.project_later(previous_profile_id: nil) }
    end
  end

  test "track_event enqueues visit projection when a profiled visit receives later events" do
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
      started_at: 5.minutes.ago.change(usec: 0)
    )

    store = Analytics::AhoyStore.new(
      ahoy: OpenStruct.new(visit_token: visit.visit_token, existing_visit_token: true)
    )

    assert_enqueued_jobs 1, only: Analytics::VisitProjectionJob do
      assert_no_enqueued_jobs only: Analytics::ProfileResolutionJob do
        store.track_event(
          name: "pageview",
          properties: { page: "/pricing" },
          time: 4.minutes.ago.change(usec: 0)
        )
      end
    end
  end

  test "classifies facebook cpc traffic as paid social" do
    now = Time.zone.now.change(usec: 0)
    Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      utm_source: "facebook_ads",
      utm_medium: "cpc",
      started_at: now
    )

    payload = sources_payload(
      {
        period: "custom",
        from: now.to_date.iso8601,
        to: now.to_date.iso8601,
        filters: {},
        advanced_filters: {},
        mode: "channels"
      },
      limit: 10,
      page: 1
    )

    assert_equal [ "Paid Social" ], payload.fetch(:results).map { |row| row.fetch(:name) }
  end

  test "normalizes plausible-style source labels for ai and collaboration referrers" do
    now = Time.zone.now.change(usec: 0)

    {
      "chatgpt.com" => "ChatGPT",
      "perplexity.ai" => "Perplexity",
      "app.slack.com" => "Slack",
      "statics.teams.cdn.office.net" => "Microsoft Teams",
      "en.wikipedia.org" => "Wikipedia"
    }.each_with_index do |(domain, _label), index|
      Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "source-normalize-#{index}",
        referring_domain: domain,
        started_at: now
      )
    end

    payload = sources_payload(
      {
        period: "custom",
        from: now.to_date.iso8601,
        to: now.to_date.iso8601,
        filters: {},
        advanced_filters: {},
        mode: "all"
      },
      limit: 20,
      page: 1
    )

    names = payload.fetch(:results).map { |row| row.fetch(:name) }
    assert_includes names, "ChatGPT"
    assert_includes names, "Perplexity"
    assert_includes names, "Slack"
    assert_includes names, "Microsoft Teams"
    assert_includes names, "Wikipedia"
  end

  test "persists normalized source dimensions on visit create" do
    visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      utm_source: "chatgpt",
      started_at: Time.zone.now.change(usec: 0)
    )

    assert_equal "ChatGPT", visit.source_label
    assert_equal "search", visit.source_kind
    assert_equal "Organic Search", visit.source_channel
    assert_equal "chatgpt.com", visit.source_favicon_domain
    assert_equal Analytics::SourceResolver.rule_version, visit.source_rule_version
    assert_equal "utm-chatgpt", visit.source_rule_id
  end

  test "source and channel filters use normalized source dimensions" do
    now = Time.zone.now.change(usec: 0)

    matching = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "facebook-paid",
      utm_source: "fbads",
      utm_medium: "cpc",
      started_at: now
    )
    Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "organic-search",
      utm_source: "chatgpt",
      started_at: now + 1.second
    )

    assert_equal [ matching.id ], filtered_visits({ "source" => "Facebook" }).pluck(:id)
    assert_equal [ matching.id ], filtered_visits({ "channel" => "Paid Social" }).pluck(:id)
  end

  test "source payload and filters fall back to legacy raw source values when normalized fields are missing" do
    now = Time.zone.now.change(usec: 0)

    legacy_visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "legacy-source",
      utm_source: "legacy-newsletter",
      utm_medium: "email",
      started_at: now
    )
    legacy_visit.update_columns(
      source_label: nil,
      source_channel: nil,
      source_kind: nil,
      source_favicon_domain: nil,
      source_rule_id: nil,
      source_rule_version: nil,
      source_match_strategy: nil
    )

    payload = sources_payload(
      {
        period: "custom",
        from: now.to_date.iso8601,
        to: now.to_date.iso8601,
        filters: {},
        advanced_filters: {},
        mode: "all"
      },
      limit: 20,
      page: 1
    )

    assert_includes payload.fetch(:results).map { |row| row.fetch(:name) }, "legacy-newsletter"
    assert_equal [ legacy_visit.id ], filtered_visits({ "source" => "legacy-newsletter" }).pluck(:id)
    assert_equal [ legacy_visit.id ], filtered_visits({ "channel" => "email" }).pluck(:id)
  end

  test "source debug payload exposes normalized and raw source details" do
    now = Time.zone.now.change(usec: 0)
    visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "source-debug",
      utm_source: "fbads",
      utm_medium: "cpc",
      referring_domain: "facebook.com",
      referrer: "https://facebook.com/campaigns/1",
      started_at: now
    )

    payload = Analytics::Sources.debug_payload(
      {
        period: "custom",
        from: now.to_date.iso8601,
        to: now.to_date.iso8601,
        filters: {},
        advanced_filters: {}
      },
      "facebook.com"
    )

    assert_equal "Facebook", payload.dig(:source, :normalized_value)
    assert_equal "social", payload.dig(:source, :kind)
    assert_equal "facebook.com", payload.dig(:source, :favicon_domain)
    assert_equal "utm-facebook-fbads", payload.fetch(:matched_rules).first.fetch(:value)
    assert_equal "facebook.com", payload.fetch(:raw_referring_domains).first.fetch(:value)
    assert_equal "fbads", payload.fetch(:raw_utm_sources).first.fetch(:value)
    assert_equal visit.started_at.iso8601, payload.fetch(:latest_samples).first.fetch(:started_at)
  end

  test "sources payload includes source info previews for normalized rows" do
    now = Time.zone.now.change(usec: 0)
    Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "source-preview",
      utm_source: "fbads",
      referring_domain: "facebook.com",
      started_at: now
    )

    payload = sources_payload(
      {
        period: "custom",
        from: now.to_date.iso8601,
        to: now.to_date.iso8601,
        filters: {},
        advanced_filters: {},
        mode: "all"
      },
      limit: 20,
      page: 1
    )

    row = payload.fetch(:results).find { |item| item.fetch(:name) == "Facebook" }

    assert_not_nil row
    assert_equal "Facebook", row.dig(:source_info, :normalized_name)
    assert_equal "facebook.com", row.dig(:source_info, :top_referring_domain)
    assert_equal "fbads", row.dig(:source_info, :top_utm_source)
  end

  test "classifies plausible-style ai search and social aliases into channels" do
    now = Time.zone.now.change(usec: 0)

    [
      { utm_source: "chatgpt", expected: "Organic Search" },
      { utm_source: "brave", expected: "Organic Search" },
      { utm_source: "slack", expected: "Organic Social" },
      { utm_source: "producthunt", expected: "Organic Social" }
    ].each_with_index do |attrs, index|
      Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "channel-alias-#{index}",
        utm_source: attrs.fetch(:utm_source),
        started_at: now + index.seconds
      )
    end

    payload = sources_payload(
      {
        period: "custom",
        from: now.to_date.iso8601,
        to: now.to_date.iso8601,
        filters: {},
        advanced_filters: {},
        mode: "channels"
      },
      limit: 20,
      page: 1
    )

    rows = payload.fetch(:results).index_by { |row| row.fetch(:name) }
    assert_equal 2, rows.fetch("Organic Search").fetch(:visitors)
    assert_equal 2, rows.fetch("Organic Social").fetch(:visitors)
  end

  test "removed imported aggregates fall back to empty hashes" do
    range = Time.zone.now.beginning_of_day..Time.zone.now.end_of_day

    assert_equal({}, Analytics::Imports.pages_aggregates(range))
    assert_equal({}, Analytics::Imports.entry_aggregates(range))
    assert_equal({}, Analytics::Imports.exit_aggregates(range))
  end

  test "live visitors prefer recent event activity over recent started_at fallback" do
    now = Time.zone.now.change(usec: 0)

    active_by_event = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "visitor-event",
      started_at: now - 20.minutes,
      latitude: 21.0285,
      longitude: 105.8542
    )
    Ahoy::Event.create!(
      visit: active_by_event,
      name: "pageview",
      properties: { page: "/docs" },
      time: now - 2.minutes
    )

    Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "visitor-started",
      started_at: now - 2.minutes,
      latitude: 37.7749,
      longitude: -122.4194
    )

    assert_equal 1, Analytics::LiveState.current_visitors(now: now)
  end

  test "live visitors fall back to recent started_at when there are no recent events" do
    now = Time.zone.now.change(usec: 0)

    Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "visitor-started",
      started_at: now - 2.minutes
    )

    assert_equal 1, Analytics::LiveState.current_visitors(now: now)
  end

  test "recent with coordinates includes visits revived by recent events" do
    now = Time.zone.now.change(usec: 0)

    old_visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "visitor-event",
      started_at: now - 30.minutes,
      latitude: 21.0285,
      longitude: 105.8542
    )
    Ahoy::Event.create!(
      visit: old_visit,
      name: "pageview",
      properties: { page: "/docs" },
      time: now - 1.minute
    )

    ids = Analytics::LiveState.active_visits_with_coordinates(now: now, window: 5.minutes).pluck(:id)

    assert_includes ids, old_visit.id
  end

  test "custom comparison range covers the full compare_to day" do
    Time.use_zone("UTC") do
      range = Analytics::Ranges.custom_compare_range(
        compare_from: "2026-03-01",
        compare_to: "2026-03-07"
      )

      assert_equal Time.zone.parse("2026-03-01 00:00:00"), range.begin
      assert_equal Time.zone.parse("2026-03-07 23:59:59.999999999"), range.end
    end
  end

  test "invalid date params fall back instead of raising" do
    travel_to Time.utc(2026, 3, 24, 15, 30, 0) do
      Time.use_zone("UTC") do
        day_range, = Analytics::Ranges.range_and_interval_for("day", nil, { date: "not-a-date" })
        custom_range, = Analytics::Ranges.range_and_interval_for(
          "custom",
          nil,
          { from: "not-a-date", to: "still-not-a-date" }
        )

        assert_equal Time.zone.parse("2026-03-24 00:00:00"), day_range.begin
        assert_equal Time.zone.parse("2026-03-24 23:59:59.999999999"), day_range.end
        assert_equal Time.zone.parse("2026-03-17 00:00:00"), custom_range.begin
        assert_equal Time.zone.parse("2026-03-23 23:59:59.999999999"), custom_range.end
      end
    end
  end

  test "current day range trims to the end of the current hour" do
    travel_to Time.utc(2026, 3, 24, 15, 30, 0) do
      Time.use_zone("UTC") do
        day_range, = Analytics::Ranges.range_and_interval_for("day", nil, {})

        trimmed = Analytics::Ranges.trim_range_to_now_if_applicable(day_range, "day")

        assert_equal Time.zone.parse("2026-03-24 15:59:59"), trimmed.end.change(usec: 0)
      end
    end
  end

  test "main graph payload marks the current hour as present for today's comparison view" do
    travel_to Time.utc(2026, 3, 24, 15, 30, 0) do
      Time.use_zone("UTC") do
        payload = main_graph_payload(
          period: "day",
          comparison: "previous_period",
          metric: "visitors",
          filters: {}
        )

        assert_equal 15, payload[:present_index]
        assert_equal 24, payload[:labels].length
        assert_equal "2026-03-24T15:00:00Z", payload[:labels][15]
      end
    end
  end

  test "main graph payload keeps the full previous day for today's comparison view" do
    travel_to Time.utc(2026, 3, 25, 15, 30, 0) do
      Time.use_zone("UTC") do
        early_previous = Ahoy::Visit.create!(
          visit_token: SecureRandom.hex(16),
          visitor_token: "graph-previous-early",
          started_at: Time.zone.parse("2026-03-24 09:00:00")
        )
        Ahoy::Event.create!(
          visit: early_previous,
          name: "pageview",
          time: Time.zone.parse("2026-03-24 09:00:00"),
          properties: { page: "/docs" }
        )

        late_previous = Ahoy::Visit.create!(
          visit_token: SecureRandom.hex(16),
          visitor_token: "graph-previous-late",
          started_at: Time.zone.parse("2026-03-24 20:00:00")
        )
        Ahoy::Event.create!(
          visit: late_previous,
          name: "pageview",
          time: Time.zone.parse("2026-03-24 20:00:00"),
          properties: { page: "/docs" }
        )

        payload = main_graph_payload(
          period: "day",
          comparison: "previous_period",
          metric: "visitors",
          filters: {}
        )

        assert_equal 24, payload[:comparison_plot].length
        assert_equal 1, payload[:comparison_plot][9]
        assert_equal 1, payload[:comparison_plot][20]
      end
    end
  end

  test "main graph payload leaves present index empty for historical days" do
    travel_to Time.utc(2026, 3, 24, 15, 30, 0) do
      Time.use_zone("UTC") do
        payload = main_graph_payload(
          period: "day",
          date: "2026-03-23",
          metric: "visitors",
          filters: {}
        )

        assert_nil payload[:present_index]
      end
    end
  end

  test "top stat change follows plausible comparison semantics" do
    assert_equal 100, Analytics::ReportMetrics.top_stat_change(:visitors, 0, 60)
    assert_equal 0, Analytics::ReportMetrics.top_stat_change(:visitors, 0, 0)
    assert_equal(-47, Analytics::ReportMetrics.top_stat_change(:visitors, 113, 60))
    assert_equal(-7, Analytics::ReportMetrics.top_stat_change(:views_per_visit, 1.90, 1.77))
    assert_in_delta(-1.3, Analytics::ReportMetrics.top_stat_change(:bounce_rate, 23.01, 21.67), 0.001)
    assert_nil Analytics::ReportMetrics.top_stat_change(:bounce_rate, 0, 21.67)
  end

  test "top stats compare today against the previous period up to the current hour" do
    travel_to Time.zone.parse("2026-03-25 17:36:00") do
      current_visit = Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "today-visitor",
        started_at: Time.zone.parse("2026-03-25 09:00:00")
      )
      Ahoy::Event.create!(
        visit: current_visit,
        name: "pageview",
        time: Time.zone.parse("2026-03-25 09:00:00"),
        properties: { page: "/docs" }
      )

      previous_in_window = Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "previous-in-window",
        started_at: Time.zone.parse("2026-03-24 09:00:00")
      )
      Ahoy::Event.create!(
        visit: previous_in_window,
        name: "pageview",
        time: Time.zone.parse("2026-03-24 09:00:00"),
        properties: { page: "/docs" }
      )

      previous_after_cutoff = Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "previous-after-cutoff",
        started_at: Time.zone.parse("2026-03-24 20:00:00")
      )
      Ahoy::Event.create!(
        visit: previous_after_cutoff,
        name: "pageview",
        time: Time.zone.parse("2026-03-24 20:00:00"),
        properties: { page: "/docs" }
      )

      payload = top_stats_payload(
        period: "day",
        comparison: "previous_period",
        match_day_of_week: false,
        filters: {}
      )

      unique_visitors = payload[:top_stats].find { |item| item[:name] == "Unique visitors" }

      assert_equal 1, unique_visitors[:value]
      assert_equal 1, unique_visitors[:comparison_value]
      assert_equal 0, unique_visitors[:change]
      assert_equal "2026-03-24T00:00:00+07:00", payload[:comparing_from]
      assert_equal "2026-03-24T17:59:59+07:00", payload[:comparing_to]
    end
  end

  test "goal-filtered top stats follow conversion context" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      converting_visit = Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "goal-converted",
        started_at: Time.zone.parse("2026-03-25 09:00:00")
      )
      Ahoy::Event.create!(
        visit: converting_visit,
        name: "Signup",
        time: Time.zone.parse("2026-03-25 09:05:00"),
        properties: {}
      )

      Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "goal-total-only",
        started_at: Time.zone.parse("2026-03-25 10:00:00")
      )

      payload = top_stats_payload(
        period: "day",
        comparison: "previous_period",
        filters: { "goal" => "Signup" }
      )

      assert_equal %w[visitors events conversion_rate], payload[:graphable_metrics]
      assert_equal [ "Unique conversions", "Total conversions", "Conversion rate" ], payload[:top_stats].drop(1).map { |item| item[:name] }
      assert_equal 1, payload[:top_stats][1][:value]
      assert_equal 1, payload[:top_stats][2][:value]
      assert_equal 50.0, payload[:top_stats][3][:value]
    end
  end

  test "configured event goals use display names and custom props" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      Analytics::Goal.create!(
        display_name: "Signup Pro",
        event_name: "Signup",
        custom_props: { "plan" => "Pro" }
      )

      matching_visit = Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "goal-pro-match",
        started_at: Time.zone.parse("2026-03-25 09:00:00")
      )
      Ahoy::Event.create!(
        visit: matching_visit,
        name: "Signup",
        time: Time.zone.parse("2026-03-25 09:05:00"),
        properties: { plan: "Pro" }
      )

      non_matching_visit = Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "goal-pro-other",
        started_at: Time.zone.parse("2026-03-25 10:00:00")
      )
      Ahoy::Event.create!(
        visit: non_matching_visit,
        name: "Signup",
        time: Time.zone.parse("2026-03-25 10:05:00"),
        properties: { plan: "Starter" }
      )

      payload = top_stats_payload(
        period: "day",
        filters: { "goal" => "Signup Pro" }
      )

      assert_equal 1, payload[:top_stats][1][:value]
      assert_equal 1, payload[:top_stats][2][:value]
      assert_equal 50.0, payload[:top_stats][3][:value]
    end
  end

  test "configured page goals count matching pageviews" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      Analytics::Goal.create!(
        display_name: "Visit Pricing",
        page_path: "/pricing",
        scroll_threshold: -1,
        custom_props: {}
      )

      matching_visit = Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "goal-page-match",
        started_at: Time.zone.parse("2026-03-25 09:00:00")
      )
      Ahoy::Event.create!(
        visit: matching_visit,
        name: "pageview",
        time: Time.zone.parse("2026-03-25 09:00:00"),
        properties: { page: "/pricing?ref=ad" }
      )

      Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "goal-page-total",
        started_at: Time.zone.parse("2026-03-25 10:00:00")
      )

      payload = top_stats_payload(
        period: "day",
        filters: { "goal" => "Visit Pricing" }
      )

      assert_equal 1, payload[:top_stats][1][:value]
      assert_equal 1, payload[:top_stats][2][:value]
      assert_equal 50.0, payload[:top_stats][3][:value]
    end
  end

  test "configured wildcard page goals match nested paths like plausible" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      Analytics::Goal.create!(
        display_name: "Visit /blog*",
        page_path: "/blog*",
        scroll_threshold: -1,
        custom_props: {}
      )

      matching_visit = Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "goal-blog-match",
        started_at: Time.zone.parse("2026-03-25 09:00:00")
      )
      Ahoy::Event.create!(
        visit: matching_visit,
        name: "pageview",
        time: Time.zone.parse("2026-03-25 09:00:00"),
        properties: { page: "/blog/how-we-seeded" }
      )

      Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "goal-blog-total",
        started_at: Time.zone.parse("2026-03-25 10:00:00")
      )

      payload = top_stats_payload(
        period: "day",
        filters: { "goal" => "Visit /blog*" }
      )

      assert_equal 1, payload[:top_stats][1][:value]
      assert_equal 1, payload[:top_stats][2][:value]
      assert_equal 50.0, payload[:top_stats][3][:value]
    end
  end

  test "configured wildcard page goals do not match sibling prefixes" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      Analytics::Goal.create!(
        display_name: "Visit /blog*",
        page_path: "/blog*",
        scroll_threshold: -1,
        custom_props: {}
      )

      Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "goal-blogger-only",
        started_at: Time.zone.parse("2026-03-25 09:00:00")
      ).tap do |visit|
        Ahoy::Event.create!(
          visit: visit,
          name: "pageview",
          time: Time.zone.parse("2026-03-25 09:00:00"),
          properties: { page: "/blogger" }
        )
      end

      payload = top_stats_payload(
        period: "day",
        filters: { "goal" => "Visit /blog*" }
      )

      assert_equal 0, payload[:top_stats][1][:value]
      assert_equal 0, payload[:top_stats][2][:value]
      assert_equal 0.0, payload[:top_stats][3][:value]
    end
  end

  test "configured scroll goals count matching engagement events" do
    Analytics::Goal.create!(
      display_name: "Scroll Docs",
      page_path: "/docs",
      scroll_threshold: 60,
      custom_props: {}
    )

    matching_visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "goal-scroll-match",
      started_at: Time.zone.parse("2026-03-24 09:00:00")
    )
    Ahoy::Event.create!(
      visit: matching_visit,
      name: "engagement",
      time: Time.zone.parse("2026-03-24 09:10:00"),
      properties: { page: "/docs", scroll_depth: 75, engaged_ms: 5_000 }
    )

    Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "goal-scroll-total",
      started_at: Time.zone.parse("2026-03-24 09:15:00")
    )

    payload = main_graph_payload(
      period: "day",
      date: "2026-03-24",
      metric: "conversion_rate",
      filters: { "goal" => "Scroll Docs" }
    )

    assert_equal 50.0, payload[:plot][9]
  end

  test "page-filtered top stats follow page context" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      visit = Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "page-visitor",
        started_at: Time.zone.parse("2026-03-25 09:00:00"),
        landing_page: "/docs"
      )

      Ahoy::Event.create!(
        visit: visit,
        name: "pageview",
        time: Time.zone.parse("2026-03-25 09:00:00"),
        properties: { page: "/docs" }
      )
      Ahoy::Event.create!(
        visit: visit,
        name: "engagement",
        time: Time.zone.parse("2026-03-25 09:00:10"),
        properties: { page: "/docs", engaged_ms: 15_000, scroll_depth: 80 }
      )

      payload = top_stats_payload(
        period: "day",
        comparison: "previous_period",
        filters: { "page" => "/docs" }
      )

      assert_equal %w[visitors visits pageviews bounce_rate scroll_depth time_on_page], payload[:graphable_metrics]
      assert_equal [ "Unique visitors", "Total visits", "Total pageviews", "Bounce rate", "Scroll depth", "Time on page" ], payload[:top_stats].drop(1).map { |item| item[:name] }
      assert_equal 0.0, payload[:top_stats][4][:value]
      assert_equal 80.0, payload[:top_stats][5][:value]
      assert_equal 15.0, payload[:top_stats][6][:value]
    end
  end

  test "page filter metrics ignore unrelated engagement cutoffs" do
    range = Time.zone.parse("2026-03-25 00:00:00")..Time.zone.parse("2026-03-25 23:59:59")

    docs_visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "docs-visitor",
      started_at: Time.zone.parse("2026-03-25 10:00:00"),
      landing_page: "/docs"
    )
    Ahoy::Event.create!(
      visit: docs_visit,
      name: "pageview",
      time: Time.zone.parse("2026-03-25 10:00:00"),
      properties: { page: "/docs" }
    )
    Ahoy::Event.create!(
      visit: docs_visit,
      name: "pageview",
      time: Time.zone.parse("2026-03-25 10:10:00"),
      properties: { page: "/pricing" }
    )

    other_visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "other-visitor",
      started_at: Time.zone.parse("2026-03-25 09:00:00"),
      landing_page: "/home"
    )
    Ahoy::Event.create!(
      visit: other_visit,
      name: "pageview",
      time: Time.zone.parse("2026-03-25 09:00:00"),
      properties: { page: "/home" }
    )
    Ahoy::Event.create!(
      visit: other_visit,
      name: "engagement",
      time: Time.zone.parse("2026-03-25 09:05:00"),
      properties: { page: "/home", engaged_ms: 1_000, scroll_depth: 10 }
    )

    metrics = Analytics::ReportMetrics.page_filter_metrics(
      range,
      Analytics::Query.new(filters: { page: "/docs" })
    )

    assert_equal 600.0, metrics[:time_on_page]
    assert_equal 0.0, metrics[:scroll_depth]
  end

  test "entry page filter keeps generic top stats context" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      visit = Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "entry-visitor",
        started_at: Time.zone.parse("2026-03-25 09:00:00"),
        landing_page: "/docs"
      )

      Ahoy::Event.create!(
        visit: visit,
        name: "pageview",
        time: Time.zone.parse("2026-03-25 09:00:00"),
        properties: { page: "/docs" }
      )
      Ahoy::Event.create!(
        visit: visit,
        name: "engagement",
        time: Time.zone.parse("2026-03-25 09:00:10"),
        properties: { page: "/docs", engaged_ms: 15_000, scroll_depth: 80 }
      )

      payload = top_stats_payload(
        period: "day",
        comparison: "previous_period",
        filters: { "entry_page" => "/docs" }
      )

      assert_equal %w[visitors visits pageviews views_per_visit bounce_rate visit_duration], payload[:graphable_metrics]
      refute_includes payload[:top_stats].drop(1).map { |item| item[:name] }, "Scroll depth"
      refute_includes payload[:top_stats].drop(1).map { |item| item[:name] }, "Time on page"
    end
  end

  test "main graph payload supports conversion rate for goal filters" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      converting_visit = Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "chart-converted",
        started_at: Time.zone.parse("2026-03-24 09:00:00")
      )
      Ahoy::Event.create!(
        visit: converting_visit,
        name: "Signup",
        time: Time.zone.parse("2026-03-24 09:10:00"),
        properties: {}
      )
      Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "chart-total-only",
        started_at: Time.zone.parse("2026-03-24 09:15:00")
      )

      payload = main_graph_payload(
        period: "day",
        date: "2026-03-24",
        metric: "conversion_rate",
        filters: { "goal" => "Signup" }
      )

      assert_equal "conversion_rate", payload[:metric]
      assert_equal 50.0, payload[:plot][9]
    end
  end

  test "main graph payload supports time on page for page filters" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      visit = Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "time-on-page-visitor",
        started_at: Time.zone.parse("2026-03-24 09:00:00"),
        landing_page: "/docs"
      )
      Ahoy::Event.create!(
        visit: visit,
        name: "pageview",
        time: Time.zone.parse("2026-03-24 09:00:00"),
        properties: { page: "/docs" }
      )
      Ahoy::Event.create!(
        visit: visit,
        name: "engagement",
        time: Time.zone.parse("2026-03-24 09:00:30"),
        properties: { page: "/docs", engaged_ms: 12_000, scroll_depth: 75 }
      )

      payload = main_graph_payload(
        period: "day",
        date: "2026-03-24",
        metric: "time_on_page",
        filters: { "page" => "/docs" }
      )

      assert_equal "time_on_page", payload[:metric]
      assert_equal 12.0, payload[:plot][9]
    end
  end

  test "complex graph metrics do not double count visits on bucket boundaries" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      visit_a = Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "boundary-a",
        started_at: Time.zone.parse("2026-03-25 10:00:00")
      )
      Ahoy::Event.create!(
        visit: visit_a,
        name: "pageview",
        time: Time.zone.parse("2026-03-25 10:00:00"),
        properties: { page: "/docs" }
      )

      visit_b = Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "boundary-b",
        started_at: Time.zone.parse("2026-03-25 11:00:00")
      )
      5.times do |index|
        Ahoy::Event.create!(
          visit: visit_b,
          name: "pageview",
          time: Time.zone.parse("2026-03-25 11:00:00") + index.seconds,
          properties: { page: "/pricing" }
        )
      end

      payload = main_graph_payload(
        period: "day",
        date: "2026-03-25",
        metric: "views_per_visit",
        filters: {}
      )

      ten_am_index = payload[:labels].index("2026-03-25T03:00:00Z")
      eleven_am_index = payload[:labels].index("2026-03-25T04:00:00Z")

      assert_equal 1.0, payload[:plot][ten_am_index]
      assert_equal 5.0, payload[:plot][eleven_am_index]
    end
  end

  test "visit metrics divide views per visit and duration by total visits" do
    range = Time.zone.parse("2026-03-25 00:00:00")..Time.zone.parse("2026-03-25 23:59:59")
    visit_with_events = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "metrics-a",
      started_at: Time.zone.parse("2026-03-25 09:00:00")
    )
    visit_without_events = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "metrics-b",
      started_at: Time.zone.parse("2026-03-25 10:00:00")
    )

    Ahoy::Event.create!(
      visit: visit_with_events,
      name: "pageview",
      time: Time.zone.parse("2026-03-25 09:00:00"),
      properties: { page: "/docs" }
    )
    Ahoy::Event.create!(
      visit: visit_with_events,
      name: "pageview",
      time: Time.zone.parse("2026-03-25 09:00:10"),
      properties: { page: "/pricing" }
    )

    metrics = Analytics::ReportMetrics.visit_metrics(
      Ahoy::Visit.where(id: [ visit_with_events.id, visit_without_events.id ]),
      Ahoy::Event.where(name: "pageview", time: range, visit_id: [ visit_with_events.id, visit_without_events.id ])
    )

    assert_equal 1.0, metrics[:pageviews_per_visit]
    assert_equal 5.0, metrics[:average_duration]
  end

  test "conversions payload ignores property filters in total visitor denominator" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      Analytics::Goal.create!(display_name: "Signup", event_name: "Signup", custom_props: {})

      converting_visit = Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "conversions-pro",
        started_at: Time.zone.parse("2026-03-25 09:00:00")
      )
      Ahoy::Event.create!(
        visit: converting_visit,
        name: "Signup",
        time: Time.zone.parse("2026-03-25 09:05:00"),
        properties: { plan: "pro" }
      )

      other_visit = Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "conversions-free",
        started_at: Time.zone.parse("2026-03-25 10:00:00")
      )
      Ahoy::Event.create!(
        visit: other_visit,
        name: "Signup",
        time: Time.zone.parse("2026-03-25 10:05:00"),
        properties: { plan: "free" }
      )

      payload = behaviors_payload(
        {
          period: "day",
          mode: "conversions",
          filters: { "prop:plan" => "pro" },
          advanced_filters: []
        },
        limit: 100,
        page: 1
      )

      row = payload.fetch(:results).find { |item| item.fetch(:name) == "Signup" }

      assert_not_nil row
      assert_equal 1, row.fetch(:uniques)
      assert_equal 50.0, row.fetch(:conversion_rate)
    end
  end

  test "goal metrics keep property filters at visit scope when conversions happen on later events" do
    qualifying_visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "goal-visit-scope-match",
      started_at: Time.zone.parse("2026-03-25 09:00:00")
    )
    Ahoy::Event.create!(
      visit: qualifying_visit,
      name: "Viewed Pricing",
      time: Time.zone.parse("2026-03-25 09:01:00"),
      properties: { plan: "pro" }
    )
    Ahoy::Event.create!(
      visit: qualifying_visit,
      name: "Signup",
      time: Time.zone.parse("2026-03-25 09:05:00"),
      properties: {}
    )

    other_visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "goal-visit-scope-total",
      started_at: Time.zone.parse("2026-03-25 10:00:00")
    )
    Ahoy::Event.create!(
      visit: other_visit,
      name: "Viewed Pricing",
      time: Time.zone.parse("2026-03-25 10:01:00"),
      properties: { plan: "free" }
    )

    totals = Analytics::ReportMetrics.goal_metric_totals(
      Time.zone.parse("2026-03-25 00:00:00")..Time.zone.parse("2026-03-25 23:59:59"),
      Analytics::Query.new(filters: { goal: "Signup", "prop:plan" => "pro" })
    )

    assert_equal 1, totals[:unique_conversions]
    assert_equal 1, totals[:total_conversions]
    assert_equal 50.0, totals[:conversion_rate]
  end

  test "observed custom events do not count as configured goals" do
    refute Analytics::Goals.available?

    visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "goal-availability",
      started_at: Time.zone.parse("2026-03-25 09:00:00")
    )
    Ahoy::Event.create!(
      visit: visit,
      name: "Signup",
      time: Time.zone.parse("2026-03-25 09:05:00"),
      properties: {}
    )

    refute Analytics::Goals.available?
  end

  test "observed custom event properties do not count as configured custom properties" do
    refute Analytics::Properties.available?

    visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "property-availability",
      started_at: Time.zone.parse("2026-03-25 09:00:00")
    )
    Ahoy::Event.create!(
      visit: visit,
      name: "Signup",
      time: Time.zone.parse("2026-03-25 09:05:00"),
      properties: { plan: "pro" }
    )

    refute Analytics::Properties.available?
  end

  test "screen size categorization matches ingestion breakpoints" do
    assert_equal "Mobile", Analytics::Devices.categorize_screen_size("575x900")
    assert_equal "Tablet", Analytics::Devices.categorize_screen_size("576x900")
    assert_equal "Tablet", Analytics::Devices.categorize_screen_size("991x900")
    assert_equal "Laptop", Analytics::Devices.categorize_screen_size("992x900")
    assert_equal "Desktop", Analytics::Devices.categorize_screen_size("1440x900")
  end

  test "search terms payload reads cached search console facts for the current site" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    connection = Analytics::GoogleSearchConsoleConnection.rotate_for_site!(
      site: site,
      attributes: {
        google_uid: "google-user-789",
        google_email: "owner@example.com",
        access_token: "access-token",
        refresh_token: "refresh-token",
        expires_at: 1.hour.from_now,
        scopes: Analytics::GoogleSearchConsole::Client::SCOPES,
        metadata: {},
        property_identifier: "sc-domain:example.test",
        property_type: "domain",
        permission_level: "siteOwner",
        last_verified_at: Time.current
      }
    )
    sync = connection.syncs.create!(
      property_identifier: connection.property_identifier,
      search_type: "web",
      from_date: Date.new(2026, 3, 25),
      to_date: Date.new(2026, 3, 25),
      started_at: Time.current,
      finished_at: Time.current,
      status: Analytics::GoogleSearchConsole::Sync::STATUS_SUCCEEDED
    )
    Analytics::GoogleSearchConsole::QueryRow.create!(
      analytics_site: site,
      sync: sync,
      date: Date.new(2026, 3, 25),
      search_type: "web",
      query: "rails",
      page: "https://docs.example.test/docs/install",
      country: "VNM",
      device: "desktop",
      clicks: 25,
      impressions: 100,
      position_impressions_sum: 320
    )

    ::Analytics::Current.site = site

    payload = Analytics::SearchTermsDatasetQuery.payload(
      query: { period: "day", date: "2026-03-25", filters: {} },
      limit: 100,
      page: 1
    )

    row = payload.fetch(:results).find { |item| item.fetch(:name) == "rails" }
    assert_not_nil row
    assert_equal 25, row.fetch(:visitors)
    assert_equal 100, row.fetch(:impressions)
    assert_equal 25.0, row.fetch(:ctr)
    assert_equal 3.2, row.fetch(:position)
  ensure
    Current.reset
  end

  test "profile resolution does not reuse a browser profile across analytics sites" do
    site_a = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    site_b = Analytics::Site.create!(name: "Blog", canonical_hostname: "blog.example.test")
    browser_id = SecureRandom.uuid

    visit_a = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "site-a-visitor",
      analytics_site: site_a,
      started_at: Time.zone.now.change(usec: 0)
    )
    profile_a = visit_a.resolve_profile_now(browser_id:, strong_keys: [], occurred_at: visit_a.started_at)

    visit_b = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "site-b-visitor",
      analytics_site: site_b,
      started_at: (Time.zone.now + 1.minute).change(usec: 0)
    )
    profile_b = visit_b.resolve_profile_now(browser_id:, strong_keys: [], occurred_at: visit_b.started_at)

    assert_not_nil profile_a
    assert_not_nil profile_b
    assert_not_equal profile_a.id, profile_b.id
    assert_equal site_a.id, profile_a.analytics_site_id
    assert_equal site_b.id, profile_b.analytics_site_id
  end

  test "sources payload scopes results to the current analytics site" do
    now = Time.zone.now.change(usec: 0)
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    other_site = Analytics::Site.create!(name: "Blog", canonical_hostname: "blog.example.test")

    Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "site-scope-docs",
      analytics_site: site,
      started_at: now,
      utm_source: "chatgpt"
    )
    Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "site-scope-blog",
      analytics_site: other_site,
      started_at: now,
      utm_source: "facebook_ads",
      utm_medium: "cpc"
    )

    ::Analytics::Current.site = site

    payload = sources_payload(
      {
        period: "custom",
        from: now.to_date.iso8601,
        to: now.to_date.iso8601,
        filters: {},
        advanced_filters: {},
        mode: "all"
      },
      limit: 20,
      page: 1
    )

    assert_equal [ "ChatGPT" ], payload.fetch(:results).map { |row| row.fetch(:name) }
  end

  private
    def sources_payload(query, **options)
      Analytics::SourcesDatasetQuery.payload(query: query, **options)
    end

    def filtered_visits(filters, advanced_filters: [])
      Analytics::VisitScope.filtered(Analytics::Query.new(filters:, advanced_filters:))
    end

    def main_graph_payload(query)
      Analytics::MainGraphQuery.payload(query: query)
    end

    def top_stats_payload(query)
      Analytics::TopStatsQuery.payload(query: query)
    end

    def behaviors_payload(query, **options)
      Analytics::BehaviorsDatasetQuery.payload(query: query, **options)
    end
end
