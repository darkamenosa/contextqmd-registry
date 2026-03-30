# frozen_string_literal: true

require "test_helper"

class Admin::AnalyticsBreakdownComparisonTest < ActiveSupport::TestCase
  include ActiveSupport::Testing::TimeHelpers

  setup do
    Rails.cache.clear
    Ahoy::Event.delete_all
    Ahoy::Visit.delete_all
    Analytics::GoogleSearchConsole::QueryRow.delete_all
    Analytics::GoogleSearchConsole::Sync.delete_all
    Analytics::GoogleSearchConsoleConnection.delete_all
    Analytics::SiteBoundary.delete_all
    Analytics::Site.delete_all
    Analytics::Setting.delete_all
    Analytics::Goal.delete_all
    Analytics::Funnel.delete_all
  end

  test "sources rows include comparison values and change when comparison is enabled" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      2.times do |index|
        Ahoy::Visit.create!(
          visit_token: SecureRandom.hex(16),
          visitor_token: "current-direct-#{index}",
          started_at: Time.zone.parse("2026-03-25 09:00:00")
        )
      end

      Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "previous-direct",
        started_at: Time.zone.parse("2026-03-24 09:00:00")
      )

      controller = build_controller_for_payloads
      payload = controller.send(
        :sources_payload,
        {
          period: "day",
          comparison: "previous_period",
          mode: "channels",
          match_day_of_week: false,
          filters: {},
          labels: {},
          with_imported: false
        },
        limit: 100,
        page: 1
      )
      row = payload.fetch(:results).find { |item| item.fetch(:name) == "Direct" }

      assert_not_nil row
      assert_includes payload.fetch(:metrics), :percentage
      assert_equal 1, row.fetch(:comparison).fetch(:visitors)
      assert_equal 100, row.fetch(:comparison).fetch(:change).fetch(:visitors)
      assert_equal 1.0, row.fetch(:comparison).fetch(:percentage)
      assert_equal 0, row.fetch(:comparison).fetch(:change).fetch(:percentage)
      assert_equal "Wed, 25 Mar 2026", payload.fetch(:meta).fetch(:date_range_label)
      assert_equal "Tue, 24 Mar 2026", payload.fetch(:meta).fetch(:comparison_date_range_label)
    end
  ensure
    Current.reset
  end

  test "pages rows include percentage comparison values" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      create_page_visit("current-a", "2026-03-25 09:00:00", "/docs")
      create_page_visit("current-b", "2026-03-25 10:00:00", "/docs")
      create_page_visit("previous-a", "2026-03-24 09:00:00", "/docs")

      controller = build_controller_for_payloads
      payload = controller.send(
        :pages_payload,
        {
          period: "day",
          comparison: "previous_period",
          mode: "pages",
          match_day_of_week: false,
          filters: {},
          labels: {},
          with_imported: false
        },
        limit: 100,
        page: 1
      )
      row = payload.fetch(:results).find { |item| item.fetch(:name) == "/docs" }

      assert_not_nil row
      assert_includes payload.fetch(:metrics), :percentage
      assert_equal 1.0, row.fetch(:percentage)
      assert_equal 1.0, row.fetch(:comparison).fetch(:percentage)
      assert_equal 0, row.fetch(:comparison).fetch(:change).fetch(:percentage)
    end
  ensure
    Current.reset
  end

  test "location rows include percentage comparison values" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      create_location_visit("current-vn-a", "2026-03-25 09:00:00", "VN", "Ho Chi Minh", "Ho Chi Minh City")
      create_location_visit("current-vn-b", "2026-03-25 10:00:00", "VN", "Ho Chi Minh", "Ho Chi Minh City")
      create_location_visit("previous-vn", "2026-03-24 09:00:00", "VN", "Ho Chi Minh", "Ho Chi Minh City")

      controller = build_controller_for_payloads
      payload = controller.send(
        :locations_payload,
        {
          period: "day",
          comparison: "previous_period",
          mode: "regions",
          match_day_of_week: false,
          filters: {},
          labels: {},
          with_imported: false
        },
        limit: 100,
        page: 1
      )
      row = payload.fetch(:results).find { |item| item.fetch(:name) == "Ho Chi Minh" }

      assert_not_nil row
      assert_includes payload.fetch(:metrics), :percentage
      assert_equal 1.0, row.fetch(:percentage)
      assert_equal 1.0, row.fetch(:comparison).fetch(:percentage)
      assert_equal 0, row.fetch(:comparison).fetch(:change).fetch(:percentage)
    end
  ensure
    Current.reset
  end

  test "page percentages use total visitors instead of summing rows" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      visit_a = create_page_visit("overlap-a", "2026-03-25 09:00:00", "/docs")
      create_pageview(visit_a, "2026-03-25 09:05:00", "/pricing")
      create_page_visit("overlap-b", "2026-03-25 10:00:00", "/docs")

      controller = build_controller_for_payloads
      payload = controller.send(
        :pages_payload,
        {
          period: "day",
          mode: "pages",
          filters: {},
          labels: {},
          with_imported: false
        }
      )

      docs = payload.fetch(:results).find { |item| item.fetch(:name) == "/docs" }
      pricing = payload.fetch(:results).find { |item| item.fetch(:name) == "/pricing" }

      assert_includes payload.fetch(:metrics), :percentage
      assert_equal 1.0, docs.fetch(:percentage)
      assert_equal 0.5, pricing.fetch(:percentage)
    end
  ensure
    Current.reset
  end

  test "source percentages use total visitors instead of summing rows" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "multi-source",
        started_at: Time.zone.parse("2026-03-25 09:00:00")
      )
      Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "multi-source",
        started_at: Time.zone.parse("2026-03-25 10:00:00"),
        referring_domain: "google.com"
      )
      Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "direct-only",
        started_at: Time.zone.parse("2026-03-25 11:00:00")
      )

      controller = build_controller_for_payloads
      payload = controller.send(
        :sources_payload,
        {
          period: "day",
          mode: "channels",
          filters: {},
          labels: {},
          with_imported: false
        }
      )

      direct = payload.fetch(:results).find { |item| item.fetch(:name) == "Direct" }
      organic_search = payload.fetch(:results).find { |item| item.fetch(:name) == "Organic Search" }

      assert_includes payload.fetch(:metrics), :percentage
      assert_equal 1.0, direct.fetch(:percentage)
      assert_equal 0.5, organic_search.fetch(:percentage)
    end
  ensure
    Current.reset
  end

  test "goal-filtered source conversion rate ignores property filters in denominator" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      converting_visit = Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "goal-pro-converter",
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
        visitor_token: "goal-pro-total",
        started_at: Time.zone.parse("2026-03-25 10:00:00")
      )
      Ahoy::Event.create!(
        visit: other_visit,
        name: "Signup",
        time: Time.zone.parse("2026-03-25 10:05:00"),
        properties: { plan: "free" }
      )

      controller = build_controller_for_payloads
      payload = controller.send(
        :sources_payload,
        {
          period: "day",
          mode: "channels",
          filters: { "goal" => "Signup", "prop:plan" => "pro" },
          labels: {},
          with_imported: false
        },
        limit: 100,
        page: 1
      )

      row = payload.fetch(:results).find { |item| item.fetch(:name) == "Direct" }

      assert_not_nil row
      assert_equal 1, row.fetch(:visitors)
      assert_equal 50.0, row.fetch(:conversion_rate)
    end
  ensure
    Current.reset
  end

  test "goal-filtered source conversion rate sorting uses relaxed denominators" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      2.times do |index|
        visit = Ahoy::Visit.create!(
          visit_token: SecureRandom.hex(16),
          visitor_token: "organic-pro-#{index}",
          started_at: Time.zone.parse("2026-03-25 09:00:00") + index.minutes,
          referring_domain: "google.com"
        )
        Ahoy::Event.create!(
          visit: visit,
          name: "Signup",
          time: Time.zone.parse("2026-03-25 09:05:00") + index.minutes,
          properties: { plan: "pro" }
        )
      end

      8.times do |index|
        Ahoy::Visit.create!(
          visit_token: SecureRandom.hex(16),
          visitor_token: "organic-total-#{index}",
          started_at: Time.zone.parse("2026-03-25 10:00:00") + index.minutes,
          referring_domain: "google.com"
        )
      end

      direct_visit = Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "direct-pro",
        started_at: Time.zone.parse("2026-03-25 11:00:00")
      )
      Ahoy::Event.create!(
        visit: direct_visit,
        name: "Signup",
        time: Time.zone.parse("2026-03-25 11:05:00"),
        properties: { plan: "pro" }
      )

      Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "direct-total",
        started_at: Time.zone.parse("2026-03-25 12:00:00")
      )

      payload = Analytics::SourcesDatasetQuery.payload(
        query: {
          period: "day",
          mode: "channels",
          filters: { "goal" => "Signup", "prop:plan" => "pro" },
          labels: {},
          with_imported: false
        },
        limit: 100,
        page: 1,
        order_by: [ "conversion_rate", "desc" ]
      )

      assert_equal "Direct", payload.fetch(:results).first.fetch(:name)
      assert_equal 50.0, payload.fetch(:results).first.fetch(:conversion_rate)
      assert_equal 20.0, payload.fetch(:results).second.fetch(:conversion_rate)
    end
  ensure
    Current.reset
  end

  test "devices payload applies advanced filters" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "chrome-visitor",
        started_at: Time.zone.parse("2026-03-25 09:00:00"),
        browser: "Chrome"
      )
      Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "safari-visitor",
        started_at: Time.zone.parse("2026-03-25 09:30:00"),
        browser: "Safari"
      )

      controller = build_controller_for_payloads
      payload = controller.send(
        :devices_payload,
        {
          period: "day",
          mode: "browsers",
          filters: {},
          advanced_filters: [ [ "is_not", "browser", "Chrome" ] ],
          labels: {},
          with_imported: false
        },
        limit: 100,
        page: 1
      )

      assert_equal [ "Safari" ], payload.fetch(:results).map { |row| row.fetch(:name) }
    end
  ensure
    Current.reset
  end

  test "locations payload applies advanced filters" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      create_location_visit("vn-visitor", "2026-03-25 09:00:00", "VN", "Ho Chi Minh", "Ho Chi Minh City")
      create_location_visit("us-visitor", "2026-03-25 10:00:00", "US", "California", "San Francisco")

      controller = build_controller_for_payloads
      payload = controller.send(
        :locations_payload,
        {
          period: "day",
          mode: "countries",
          filters: {},
          advanced_filters: [ [ "is_not", "country", "VN" ] ],
          labels: {},
          with_imported: false
        },
        limit: 100,
        page: 1
      )

      assert_equal [ "United States" ], payload.fetch(:results).map { |row| row.fetch(:name) }
    end
  ensure
    Current.reset
  end

  test "referrers payload uses unique direct visitors and advanced filters" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "direct-chrome",
        started_at: Time.zone.parse("2026-03-25 09:00:00"),
        browser: "Chrome"
      )
      Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "direct-safari",
        started_at: Time.zone.parse("2026-03-25 09:05:00"),
        browser: "Safari"
      )

      payload = Analytics::ReferrersDatasetQuery.payload(
        query: {
          period: "day",
          filters: {},
          advanced_filters: [ [ "is_not", "browser", "Chrome" ] ]
        },
        source: "Direct / None",
        limit: 100,
        page: 1
      )

      row = payload.fetch(:results).first
      assert_equal "Direct / None", row.fetch(:name)
      assert_equal 1, row.fetch(:visitors)
    end
  ensure
    Current.reset
  end

  test "referrers goal sorting uses relaxed denominators" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      2.times do |index|
        visit = Ahoy::Visit.create!(
          visit_token: SecureRandom.hex(16),
          visitor_token: "google-a-pro-#{index}",
          started_at: Time.zone.parse("2026-03-25 09:00:00") + index.minutes,
          referring_domain: "google.com",
          referrer: "https://google.com/search?q=alpha"
        )
        Ahoy::Event.create!(
          visit: visit,
          name: "Signup",
          time: Time.zone.parse("2026-03-25 09:05:00") + index.minutes,
          properties: { plan: "pro" }
        )
      end

      8.times do |index|
        Ahoy::Visit.create!(
          visit_token: SecureRandom.hex(16),
          visitor_token: "google-a-total-#{index}",
          started_at: Time.zone.parse("2026-03-25 10:00:00") + index.minutes,
          referring_domain: "google.com",
          referrer: "https://google.com/search?q=alpha"
        )
      end

      visit = Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "google-b-pro",
        started_at: Time.zone.parse("2026-03-25 11:00:00"),
        referring_domain: "google.com",
        referrer: "https://google.com/search?q=beta"
      )
      Ahoy::Event.create!(
        visit: visit,
        name: "Signup",
        time: Time.zone.parse("2026-03-25 11:05:00"),
        properties: { plan: "pro" }
      )

      Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "google-b-total",
        started_at: Time.zone.parse("2026-03-25 11:10:00"),
        referring_domain: "google.com",
        referrer: "https://google.com/search?q=beta"
      )

      payload = Analytics::ReferrersDatasetQuery.payload(
        query: {
          period: "day",
          filters: { "goal" => "Signup", "prop:plan" => "pro" }
        },
        source: "google.com",
        limit: 100,
        page: 1,
        order_by: [ "conversion_rate", "desc" ]
      )

      assert_equal "https://google.com/search?q=beta", payload.fetch(:results).first.fetch(:name)
      assert_equal 50.0, payload.fetch(:results).first.fetch(:conversion_rate)
      assert_equal 20.0, payload.fetch(:results).second.fetch(:conversion_rate)
    end
  ensure
    Current.reset
  end

  test "referrers goal denominators count unique visitors in unpaginated fallback" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      first_visit = Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "google-repeat-visitor",
        started_at: Time.zone.parse("2026-03-25 09:00:00"),
        referring_domain: "google.com",
        referrer: "https://google.com/search?q=alpha"
      )
      Ahoy::Event.create!(
        visit: first_visit,
        name: "Signup",
        time: Time.zone.parse("2026-03-25 09:05:00"),
        properties: {}
      )
      Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "google-repeat-visitor",
        started_at: Time.zone.parse("2026-03-25 09:10:00"),
        referring_domain: "google.com",
        referrer: "https://google.com/search?q=alpha"
      )

      payload = Analytics::ReferrersDatasetQuery.payload(
        query: {
          period: "day",
          filters: { "goal" => "Signup" }
        },
        source: "google.com",
        limit: 100,
        page: 1
      )

      row = payload.fetch(:results).find { |item| item.fetch(:name) == "https://google.com/search?q=alpha" }

      assert_not_nil row
      assert_equal 1, row.fetch(:visitors)
      assert_equal 100.0, row.fetch(:conversion_rate)
    end
  ensure
    Current.reset
  end

  test "screen size goal sorting uses conversion rate" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      3.times do |index|
        Ahoy::Visit.create!(
          visit_token: SecureRandom.hex(16),
          visitor_token: "desktop-#{index}",
          started_at: Time.zone.parse("2026-03-25 09:00:00") + index.minutes,
          screen_size: "1440x900"
        )
      end

      mobile_visit = Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "mobile-converter",
        started_at: Time.zone.parse("2026-03-25 10:00:00"),
        screen_size: "375x812"
      )
      Ahoy::Event.create!(
        visit: mobile_visit,
        name: "Signup",
        time: Time.zone.parse("2026-03-25 10:05:00"),
        properties: {}
      )

      payload = Analytics::DevicesDatasetQuery.payload(
        query: {
          period: "day",
          mode: "screen-sizes",
          filters: { "goal" => "Signup" },
          labels: {},
          with_imported: false
        },
        limit: 100,
        page: 1,
        order_by: [ "conversion_rate", "desc" ]
      )

      assert_equal "Mobile", payload.fetch(:results).first.fetch(:name)
      assert_equal 100.0, payload.fetch(:results).first.fetch(:conversion_rate)
    end
  ensure
    Current.reset
  end

  test "browser goal sorting normalizes unknown names before comparing conversion rates" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      2.times do |index|
        visit = Ahoy::Visit.create!(
          visit_token: SecureRandom.hex(16),
          visitor_token: "unknown-browser-#{index}",
          started_at: Time.zone.parse("2026-03-25 09:00:00") + index.minutes,
          browser: nil
        )
        Ahoy::Event.create!(
          visit: visit,
          name: "Signup",
          time: Time.zone.parse("2026-03-25 09:05:00") + index.minutes,
          properties: {}
        )
      end

      2.times do |index|
        visit = Ahoy::Visit.create!(
          visit_token: SecureRandom.hex(16),
          visitor_token: "chrome-browser-#{index}",
          started_at: Time.zone.parse("2026-03-25 10:00:00") + index.minutes,
          browser: "Chrome"
        )
        next if index.zero?

        Ahoy::Event.create!(
          visit: visit,
          name: "Signup",
          time: Time.zone.parse("2026-03-25 10:05:00") + index.minutes,
          properties: {}
        )
      end

      payload = Analytics::DevicesDatasetQuery.payload(
        query: {
          period: "day",
          mode: "browsers",
          filters: { "goal" => "Signup" },
          labels: {},
          with_imported: false
        },
        limit: 100,
        page: 1,
        order_by: [ "conversion_rate", "desc" ]
      )

      assert_equal "(unknown)", payload.fetch(:results).first.fetch(:name)
      assert_equal 100.0, payload.fetch(:results).first.fetch(:conversion_rate)
      assert_equal "Chrome", payload.fetch(:results).second.fetch(:name)
      assert_equal 50.0, payload.fetch(:results).second.fetch(:conversion_rate)
    end
  ensure
    Current.reset
  end

  test "referrers comparison values are attached when comparison is enabled" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "current-referrer-a",
        started_at: Time.zone.parse("2026-03-25 09:00:00"),
        referring_domain: "google.com",
        referrer: "https://google.com/search?q=alpha"
      )
      Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "current-referrer-b",
        started_at: Time.zone.parse("2026-03-25 10:00:00"),
        referring_domain: "google.com",
        referrer: "https://google.com/search?q=alpha"
      )
      Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "previous-referrer",
        started_at: Time.zone.parse("2026-03-24 09:00:00"),
        referring_domain: "google.com",
        referrer: "https://google.com/search?q=alpha"
      )

      controller = build_controller_for_payloads
      payload = controller.send(
        :referrers_payload,
        {
          period: "day",
          comparison: "previous_period",
          match_day_of_week: false,
          filters: {},
          labels: {},
          with_imported: false
        },
        "google.com",
        limit: 100,
        page: 1
      )

      row = payload.fetch(:results).find { |item| item.fetch(:name) == "https://google.com/search?q=alpha" }
      assert_not_nil row
      assert_equal 1, row.fetch(:comparison).fetch(:visitors)
      assert_equal 100, row.fetch(:comparison).fetch(:change).fetch(:visitors)
      assert_equal "Wed, 25 Mar 2026", payload.fetch(:meta).fetch(:date_range_label)
      assert_equal "Tue, 24 Mar 2026", payload.fetch(:meta).fetch(:comparison_date_range_label)
    end
  ensure
    Current.reset
  end

  test "search terms comparison values are attached when comparison is enabled" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
      connection = Analytics::GoogleSearchConsoleConnection.rotate_for_site!(
        site: site,
        attributes: {
          google_uid: "google-user-#{SecureRandom.hex(4)}",
          google_email: "owner@example.com",
          access_token: "access-token",
          refresh_token: "refresh-token",
          expires_at: 1.hour.from_now,
          scopes: Analytics::GoogleSearchConsole::Client::SCOPES,
          metadata: {},
          property_identifier: "sc-domain:docs.example.test",
          property_type: "domain",
          permission_level: "siteOwner",
          last_verified_at: Time.current
        }
      )
      sync = connection.syncs.create!(
        property_identifier: connection.property_identifier,
        search_type: "web",
        from_date: Date.new(2026, 3, 24),
        to_date: Date.new(2026, 3, 25),
        started_at: Time.current,
        finished_at: Time.current,
        status: Analytics::GoogleSearchConsole::Sync::STATUS_SUCCEEDED
      )
      ::Analytics::Current.site = site

      Analytics::GoogleSearchConsole::QueryRow.create!(
        analytics_site: site,
        sync: sync,
        date: Date.new(2026, 3, 25),
        search_type: "web",
        query: "rails",
        page: "https://docs.example.test/docs/install",
        country: "VNM",
        device: "desktop",
        clicks: 2,
        impressions: 10,
        position_impressions_sum: 34
      )
      Analytics::GoogleSearchConsole::QueryRow.create!(
        analytics_site: site,
        sync: sync,
        date: Date.new(2026, 3, 24),
        search_type: "web",
        query: "rails",
        page: "https://docs.example.test/docs/install",
        country: "VNM",
        device: "desktop",
        clicks: 1,
        impressions: 8,
        position_impressions_sum: 28
      )

      controller = build_controller_for_payloads
      query = {
        period: "day",
        comparison: "previous_period",
        match_day_of_week: false,
        filters: {},
        labels: {},
        with_imported: false
      }
      controller.instance_variable_set(:@query, query)
      body, status = controller.send(
        :search_terms_response,
        query,
        limit: 100,
        page: 1,
        search: nil
      )

      assert_equal :ok, status
      row = body.fetch("results").find { |item| item.fetch("name") == "rails" }
      assert_not_nil row
      assert_equal 1, row.fetch("comparison").fetch("visitors")
      assert_equal 100, row.fetch("comparison").fetch("change").fetch("visitors")
      assert_equal "Wed, 25 Mar 2026", body.fetch("meta").fetch("dateRangeLabel")
      assert_equal "Tue, 24 Mar 2026", body.fetch("meta").fetch("comparisonDateRangeLabel")
    end
  ensure
    Current.reset
  end

  test "list comparisons for today ignore previous-period rows after the current hour cutoff" do
    travel_to Time.zone.parse("2026-03-25 17:36:00") do
      Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "current-google",
        started_at: Time.zone.parse("2026-03-25 09:00:00"),
        referring_domain: "google.com"
      )
      Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "previous-google-early",
        started_at: Time.zone.parse("2026-03-24 09:00:00"),
        referring_domain: "google.com"
      )
      Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "previous-google-late",
        started_at: Time.zone.parse("2026-03-24 20:00:00"),
        referring_domain: "google.com"
      )

      controller = build_controller_for_payloads
      payload = controller.send(
        :sources_payload,
        {
          period: "day",
          comparison: "previous_period",
          mode: "sources",
          match_day_of_week: false,
          filters: {},
          labels: {},
          with_imported: false
        },
        limit: 100,
        page: 1
      )

      row = payload.fetch(:results).find { |item| item.fetch(:name) == "Google" }

      assert_not_nil row
      assert_equal 1, row.fetch(:comparison).fetch(:visitors)
      assert_equal 0, row.fetch(:comparison).fetch(:change).fetch(:visitors)
      assert_equal "Tue, 24 Mar 2026", payload.fetch(:meta).fetch(:comparison_date_range_label)
    end
  ensure
    Current.reset
  end

  test "comparison rows are matched against the current page even when they fall outside comparison ranking" do
    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      3.times do |index|
        Ahoy::Visit.create!(
          visit_token: SecureRandom.hex(16),
          visitor_token: "current-target-#{index}",
          started_at: Time.zone.parse("2026-03-25 09:00:00") + index.minutes,
          referring_domain: "target.example"
        )
      end

      Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "previous-target",
        started_at: Time.zone.parse("2026-03-24 09:00:00"),
        referring_domain: "target.example"
      )

      501.times do |index|
        2.times do |visit_index|
          Ahoy::Visit.create!(
            visit_token: SecureRandom.hex(16),
            visitor_token: "previous-ranked-#{index}-#{visit_index}",
            started_at: Time.zone.parse("2026-03-24 10:00:00") + index.seconds + visit_index.minutes,
            referring_domain: "ranked-#{index}.example"
          )
        end
      end

      controller = build_controller_for_payloads
      payload = controller.send(
        :sources_payload,
        {
          period: "day",
          comparison: "previous_period",
          mode: "sources",
          match_day_of_week: false,
          filters: {},
          labels: {},
          with_imported: false
        },
        limit: 100,
        page: 1
      )

      row = payload.fetch(:results).find { |item| item.fetch(:name) == "target.example" }

      assert_not_nil row
      assert_equal 1, row.fetch(:comparison).fetch(:visitors)
      assert_equal 200, row.fetch(:comparison).fetch(:change).fetch(:visitors)
    end
  ensure
    Current.reset
  end

  private
    def build_controller_for_payloads
      Class.new(Admin::Analytics::BaseController) do
        public :devices_payload, :locations_payload, :pages_payload, :referrers_payload, :search_terms_response, :sources_payload

        def params
          ActionController::Parameters.new
        end

        def action_name
          "index"
        end

        def gsc_configured?
          true
        end

        def unsupported_gsc_filters?(_query)
          false
        end
      end.new
    end

    def create_page_visit(visitor_token, started_at, path)
      visit = Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: visitor_token,
        started_at: Time.zone.parse(started_at),
        landing_page: path
      )
      create_pageview(visit, started_at, path)
      visit
    end

    def create_pageview(visit, at, path)
      Ahoy::Event.create!(
        visit: visit,
        name: "pageview",
        time: Time.zone.parse(at),
        properties: { page: path }
      )
    end

    def create_location_visit(visitor_token, started_at, country, region, city)
      Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: visitor_token,
        started_at: Time.zone.parse(started_at),
        country: country,
        region: region,
        city: city
      )
    end
end
