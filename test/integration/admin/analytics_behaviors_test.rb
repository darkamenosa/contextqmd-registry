# frozen_string_literal: true

require "test_helper"

class Admin::AnalyticsBehaviorsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Ahoy::Event.delete_all
    Ahoy::Visit.delete_all
    AnalyticsSetting.delete_all
    Goal.delete_all
    Funnel.delete_all
  end

  test "behaviors props endpoint returns real property keys and selected value breakdown" do
    staff_identity, = create_tenant(
      email: "staff-behaviors-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Behaviors"
    )
    staff_identity.update!(staff: true)

    visit_one = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      started_at: Time.zone.now.change(usec: 0)
    )
    visit_two = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      started_at: Time.zone.now.change(usec: 0)
    )

    Ahoy::Event.create!(
      visit: visit_one,
      name: "signup",
      properties: { plan: "Pro", source: "Ads" },
      time: Time.zone.now.change(usec: 0)
    )
    Ahoy::Event.create!(
      visit: visit_two,
      name: "signup",
      properties: { plan: "Starter", source: "Referral" },
      time: Time.zone.now.change(usec: 0)
    )
    Ahoy::Event.create!(
      visit: visit_two,
      name: "pageview",
      properties: { page: "/pricing", title: "Pricing" },
      time: Time.zone.now.change(usec: 0)
    )

    sign_in(staff_identity)

    get "/admin/analytics/behaviors",
        params: { period: "day", mode: "props", property: "plan", with_imported: "false" },
        headers: { "ACCEPT" => "application/json" }

    assert_response :success

    payload = JSON.parse(response.body)
    assert_equal %w[plan source], payload.fetch("propertyKeys")
    assert_equal "plan", payload.fetch("activeProperty")
    assert_equal %w[visitors events percentage], payload.fetch("list").fetch("metrics")
    assert_equal "Events", payload.fetch("list").fetch("meta").fetch("metricLabels").fetch("events")

    rows = payload.fetch("list").fetch("results")
    assert_equal [ "Pro", "Starter" ], rows.map { |row| row.fetch("name") }.sort
    assert_equal 1, rows.find { |row| row.fetch("name") == "Pro" }.fetch("events")
  ensure
    Current.reset
  end

  test "behaviors props endpoint applies property filters to displayed values" do
    staff_identity, = create_tenant(
      email: "staff-behaviors-filter-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Behaviors Filter"
    )
    staff_identity.update!(staff: true)

    visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      started_at: Time.zone.now.change(usec: 0)
    )

    Ahoy::Event.create!(
      visit: visit,
      name: "signup",
      properties: { plan: "Pro" },
      time: Time.zone.now.change(usec: 0)
    )
    Ahoy::Event.create!(
      visit: visit,
      name: "signup",
      properties: { plan: "Starter" },
      time: Time.zone.now.change(usec: 0)
    )

    sign_in(staff_identity)

    get "/admin/analytics/behaviors?period=day&mode=props&property=plan&f=is,prop:plan,Pro",
        headers: { "ACCEPT" => "application/json" }

    assert_response :success

    rows = JSON.parse(response.body).fetch("list").fetch("results")
    assert_equal [ "Pro" ], rows.map { |row| row.fetch("name") }
  ensure
    Current.reset
  end

  test "behaviors props endpoint keeps non-matching property values for advanced is_not filters" do
    staff_identity, = create_tenant(
      email: "staff-behaviors-advanced-prop-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Behaviors Advanced Prop"
    )
    staff_identity.update!(staff: true)

    visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      started_at: Time.zone.now.change(usec: 0)
    )

    Ahoy::Event.create!(
      visit: visit,
      name: "signup",
      properties: { plan: "Pro" },
      time: Time.zone.now.change(usec: 0)
    )
    Ahoy::Event.create!(
      visit: visit,
      name: "signup",
      properties: { plan: "Starter" },
      time: Time.zone.now.change(usec: 0)
    )

    sign_in(staff_identity)

    get "/admin/analytics/behaviors?period=day&mode=props&property=plan&f=is_not,prop:plan,Pro",
        headers: { "ACCEPT" => "application/json" }

    assert_response :success

    rows = JSON.parse(response.body).fetch("list").fetch("results")
    assert_equal [ "Starter" ], rows.map { |row| row.fetch("name") }
    assert_equal 1, rows.first.fetch("visitors")
    assert_equal 1, rows.first.fetch("events")
  ensure
    Current.reset
  end

  test "behaviors conversions endpoint returns uniques instead of visitors" do
    staff_identity, = create_tenant(
      email: "staff-behaviors-goals-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Behaviors Goals"
    )
    staff_identity.update!(staff: true)

    visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      started_at: Time.zone.now.change(usec: 0)
    )

    2.times do
      Ahoy::Event.create!(
        visit: visit,
        name: "Signup",
        properties: { plan: "Pro" },
        time: Time.zone.now.change(usec: 0)
      )
    end

    sign_in(staff_identity)

    get "/admin/analytics/behaviors",
        params: { period: "day", mode: "conversions", with_imported: "false" },
        headers: { "ACCEPT" => "application/json" }

    assert_response :success

    payload = JSON.parse(response.body)
    assert_equal %w[uniques total conversion_rate], payload.fetch("metrics")

    row = payload.fetch("results").find { |entry| entry.fetch("name") == "Signup" }
    assert_equal 1, row.fetch("uniques")
    assert_equal 2, row.fetch("total")
    assert_equal false, row.key?("visitors")
  ensure
    Current.reset
  end

  test "behaviors conversions endpoint prefers configured goals over raw event discovery" do
    staff_identity, = create_tenant(
      email: "staff-behaviors-config-goals-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Behaviors Config Goals"
    )
    staff_identity.update!(staff: true)

    Goal.create!(display_name: "Signup", event_name: "Signup", custom_props: {})

    visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      started_at: Time.zone.now.change(usec: 0)
    )

    Ahoy::Event.create!(
      visit: visit,
      name: "Purchase",
      properties: { amount: "99" },
      time: Time.zone.now.change(usec: 0)
    )

    sign_in(staff_identity)

    get "/admin/analytics/behaviors",
        params: { period: "day", mode: "conversions", with_imported: "false" },
        headers: { "ACCEPT" => "application/json" }

    assert_response :success

    rows = JSON.parse(response.body).fetch("results")
    assert_equal [ "Signup" ], rows.map { |row| row.fetch("name") }
    assert_equal 0, rows.first.fetch("uniques")
    assert_equal 0, rows.first.fetch("total")
  ensure
    Current.reset
  end

  test "behaviors conversions endpoint supports configured page and scroll goals" do
    staff_identity, = create_tenant(
      email: "staff-behaviors-page-scroll-goals-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Behaviors Page Scroll Goals"
    )
    staff_identity.update!(staff: true)

    Goal.create!(display_name: "Visit /blog*", page_path: "/blog*", scroll_threshold: -1, custom_props: {})
    Goal.create!(display_name: "Scroll Docs", page_path: "/docs/getting-started", scroll_threshold: 60, custom_props: {})

    page_visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      started_at: Time.zone.now.change(usec: 0)
    )
    Ahoy::Event.create!(
      visit: page_visit,
      name: "pageview",
      properties: { page: "/blog/how-plausible-works" },
      time: Time.zone.now.change(usec: 0)
    )

    scroll_visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      started_at: Time.zone.now.change(usec: 0)
    )
    Ahoy::Event.create!(
      visit: scroll_visit,
      name: "engagement",
      properties: { page: "/docs/getting-started", scroll_depth: 75, engaged_ms: 4_000 },
      time: Time.zone.now.change(usec: 0)
    )

    sign_in(staff_identity)

    get "/admin/analytics/behaviors",
        params: { period: "day", mode: "conversions", with_imported: "false" },
        headers: { "ACCEPT" => "application/json" }

    assert_response :success

    rows = JSON.parse(response.body).fetch("results")
    assert_equal 1, rows.find { |row| row.fetch("name") == "Visit /blog*" }.fetch("uniques")
    assert_equal 1, rows.find { |row| row.fetch("name") == "Scroll Docs" }.fetch("uniques")
  ensure
    Current.reset
  end

  test "behaviors props endpoint supports configured page goals" do
    staff_identity, = create_tenant(
      email: "staff-behaviors-page-goal-props-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Behaviors Page Goal Props"
    )
    staff_identity.update!(staff: true)

    Goal.create!(display_name: "Visit /blog*", page_path: "/blog*", scroll_threshold: -1, custom_props: {})

    matching_visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "page-goal-props-match",
      started_at: Time.zone.now.change(usec: 0)
    )
    Ahoy::Event.create!(
      visit: matching_visit,
      name: "pageview",
      properties: { page: "/blog/how-plausible-works", plan: "Pro" },
      time: Time.zone.now.change(usec: 0)
    )

    non_matching_visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "page-goal-props-total",
      started_at: Time.zone.now.change(usec: 0)
    )
    Ahoy::Event.create!(
      visit: non_matching_visit,
      name: "pageview",
      properties: { page: "/pricing", plan: "Starter" },
      time: Time.zone.now.change(usec: 0)
    )

    sign_in(staff_identity)

    get "/admin/analytics/behaviors?period=day&mode=props&property=plan&with_imported=false&f=is,goal,Visit%20%2Fblog*",
        headers: { "ACCEPT" => "application/json" }

    assert_response :success

    payload = JSON.parse(response.body)
    assert_equal %w[visitors events conversion_rate], payload.fetch("list").fetch("metrics")
    assert_equal [ "plan" ], payload.fetch("propertyKeys")

    rows = payload.fetch("list").fetch("results")
    assert_equal [ "Pro" ], rows.map { |row| row.fetch("name") }
    assert_equal 1, rows.first.fetch("visitors")
    assert_equal 1, rows.first.fetch("events")
    assert_in_delta 50.0, rows.first.fetch("conversionRate"), 0.001
  ensure
    Current.reset
  end

  test "behaviors props endpoint uses conversion rate when goal filter is active" do
    staff_identity, = create_tenant(
      email: "staff-behaviors-props-goal-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Behaviors Props Goal"
    )
    staff_identity.update!(staff: true)

    visit_one = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "props-goal-a",
      started_at: Time.zone.now.change(usec: 0)
    )
    visit_two = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "props-goal-b",
      started_at: Time.zone.now.change(usec: 0)
    )

    Ahoy::Event.create!(
      visit: visit_one,
      name: "Signup",
      properties: { plan: "Pro" },
      time: Time.zone.now.change(usec: 0)
    )
    2.times do
      Ahoy::Event.create!(
        visit: visit_two,
        name: "Signup",
        properties: { plan: "Starter" },
        time: Time.zone.now.change(usec: 0)
      )
    end

    sign_in(staff_identity)

    get "/admin/analytics/behaviors?period=day&mode=props&property=plan&with_imported=false&f=is,goal,Signup",
        headers: { "ACCEPT" => "application/json" }

    assert_response :success

    payload = JSON.parse(response.body)
    assert_equal %w[visitors events conversion_rate], payload.fetch("list").fetch("metrics")
    starter = payload.fetch("list").fetch("results").find { |row| row.fetch("name") == "Starter" }
    assert_equal 1, starter.fetch("visitors")
    assert_equal 2, starter.fetch("events")
    assert_in_delta 50.0, starter.fetch("conversionRate"), 0.001
  ensure
    Current.reset
  end

  test "behaviors props endpoint prefers configured property keys over discovered ones" do
    staff_identity, = create_tenant(
      email: "staff-behaviors-config-props-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Behaviors Config Props"
    )
    staff_identity.update!(staff: true)

    AnalyticsSetting.set_json("allowed_event_props", [ "plan" ])

    visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      started_at: Time.zone.now.change(usec: 0)
    )

    Ahoy::Event.create!(
      visit: visit,
      name: "Signup",
      properties: { plan: "Pro", source: "Ads" },
      time: Time.zone.now.change(usec: 0)
    )

    sign_in(staff_identity)

    get "/admin/analytics/behaviors",
        params: { period: "day", mode: "props", with_imported: "false" },
        headers: { "ACCEPT" => "application/json" }

    assert_response :success

    payload = JSON.parse(response.body)
    assert_equal [ "plan" ], payload.fetch("propertyKeys")
    assert_equal "plan", payload.fetch("activeProperty")
  ensure
    Current.reset
  end

  test "behaviors props endpoint attaches comparison values" do
    staff_identity, = create_tenant(
      email: "staff-behaviors-props-compare-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Behaviors Props Compare"
    )
    staff_identity.update!(staff: true)

    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      current_visit = Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "props-current",
        started_at: Time.zone.parse("2026-03-25 09:00:00")
      )
      previous_visit = Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "props-previous",
        started_at: Time.zone.parse("2026-03-24 09:00:00")
      )

      Ahoy::Event.create!(
        visit: current_visit,
        name: "Signup",
        properties: { plan: "Pro" },
        time: Time.zone.parse("2026-03-25 09:00:00")
      )
      2.times do
        Ahoy::Event.create!(
          visit: previous_visit,
          name: "Signup",
          properties: { plan: "Pro" },
          time: Time.zone.parse("2026-03-24 09:00:00")
        )
      end

      sign_in(staff_identity)

      get "/admin/analytics/behaviors",
          params: { period: "day", mode: "props", property: "plan", comparison: "previous_period", match_day_of_week: "false", with_imported: "false" },
          headers: { "ACCEPT" => "application/json" }

      assert_response :success

      payload = JSON.parse(response.body)
      row = payload.fetch("list").fetch("results").find { |entry| entry.fetch("name") == "Pro" }
      assert_equal 1, row.fetch("comparison").fetch("visitors")
      assert_equal 2, row.fetch("comparison").fetch("events")
    end
  ensure
    Current.reset
  end

  test "behaviors conversions endpoint attaches comparison values" do
    staff_identity, = create_tenant(
      email: "staff-behaviors-conv-compare-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Behaviors Conv Compare"
    )
    staff_identity.update!(staff: true)

    travel_to Time.zone.parse("2026-03-25 14:00:00") do
      current_visit = Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "conv-current",
        started_at: Time.zone.parse("2026-03-25 09:00:00")
      )
      previous_visit = Ahoy::Visit.create!(
        visit_token: SecureRandom.hex(16),
        visitor_token: "conv-previous",
        started_at: Time.zone.parse("2026-03-24 09:00:00")
      )

      Ahoy::Event.create!(
        visit: current_visit,
        name: "Signup",
        properties: {},
        time: Time.zone.parse("2026-03-25 09:00:00")
      )
      2.times do
        Ahoy::Event.create!(
          visit: previous_visit,
          name: "Signup",
          properties: {},
          time: Time.zone.parse("2026-03-24 09:00:00")
        )
      end

      sign_in(staff_identity)

      get "/admin/analytics/behaviors",
          params: { period: "day", mode: "conversions", comparison: "previous_period", match_day_of_week: "false", with_imported: "false" },
          headers: { "ACCEPT" => "application/json" }

      assert_response :success

      payload = JSON.parse(response.body)
      row = payload.fetch("results").find { |entry| entry.fetch("name") == "Signup" }
      assert_equal 1, row.fetch("comparison").fetch("uniques")
      assert_equal 2, row.fetch("comparison").fetch("total")
    end
  ensure
    Current.reset
  end

  test "behaviors props endpoint applies advanced filters to visit scope" do
    staff_identity, = create_tenant(
      email: "staff-behaviors-advanced-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Behaviors Advanced"
    )
    staff_identity.update!(staff: true)

    chrome_visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      browser: "Chrome",
      started_at: Time.zone.now.change(usec: 0)
    )
    safari_visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      browser: "Safari",
      started_at: Time.zone.now.change(usec: 0)
    )

    Ahoy::Event.create!(
      visit: chrome_visit,
      name: "signup",
      properties: { plan: "Pro" },
      time: Time.zone.now.change(usec: 0)
    )
    Ahoy::Event.create!(
      visit: safari_visit,
      name: "signup",
      properties: { plan: "Starter" },
      time: Time.zone.now.change(usec: 0)
    )

    sign_in(staff_identity)

    get "/admin/analytics/behaviors?period=day&mode=props&property=plan&f=is_not,browser,Chrome",
        headers: { "ACCEPT" => "application/json" }

    assert_response :success

    rows = JSON.parse(response.body).fetch("list").fetch("results")
    assert_equal [ "Starter" ], rows.map { |row| row.fetch("name") }
  ensure
    Current.reset
  end

  test "behaviors funnels endpoint applies advanced filters" do
    staff_identity, = create_tenant(
      email: "staff-behaviors-funnels-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Behaviors Funnels"
    )
    staff_identity.update!(staff: true)

    Funnel.create!(
      name: "Signup Funnel",
      steps: [
        { name: "Signup", type: "event", match: "equals", value: "Signup" }
      ]
    )

    chrome_visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      browser: "Chrome",
      started_at: Time.zone.now.change(usec: 0)
    )
    safari_visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      browser: "Safari",
      started_at: Time.zone.now.change(usec: 0)
    )

    Ahoy::Event.create!(
      visit: chrome_visit,
      name: "Signup",
      properties: {},
      time: Time.zone.now.change(usec: 0)
    )
    Ahoy::Event.create!(
      visit: safari_visit,
      name: "Signup",
      properties: {},
      time: Time.zone.now.change(usec: 0)
    )

    sign_in(staff_identity)

    get "/admin/analytics/behaviors?period=day&mode=funnels&funnel=Signup+Funnel&f=is_not,browser,Chrome",
        headers: { "ACCEPT" => "application/json" }

    assert_response :success

    payload = JSON.parse(response.body)
    assert_equal 1, payload.fetch("active").fetch("steps").first.fetch("visitors")
  ensure
    Current.reset
  end

  test "behaviors funnels endpoint returns explicit funnel stats" do
    staff_identity, = create_tenant(
      email: "staff-behaviors-funnels-stats-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Behaviors Funnel Stats"
    )
    staff_identity.update!(staff: true)

    Funnel.create!(
      name: "Signup Funnel",
      steps: [
        { name: "View pricing", type: "page", match: "equals", value: "/pricing" },
        { name: "Signup", type: "event", match: "equals", value: "Signup" }
      ]
    )

    completed_visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "funnel-complete",
      started_at: Time.zone.now.change(usec: 0)
    )
    dropped_visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "funnel-drop",
      started_at: Time.zone.now.change(usec: 0)
    )
    skipped_visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: "funnel-skip",
      started_at: Time.zone.now.change(usec: 0)
    )

    Ahoy::Event.create!(
      visit: completed_visit,
      name: "pageview",
      properties: { page: "/pricing" },
      time: Time.zone.now.change(usec: 0)
    )
    Ahoy::Event.create!(
      visit: completed_visit,
      name: "Signup",
      properties: {},
      time: (Time.zone.now + 1.minute).change(usec: 0)
    )

    Ahoy::Event.create!(
      visit: dropped_visit,
      name: "pageview",
      properties: { page: "/pricing" },
      time: Time.zone.now.change(usec: 0)
    )

    Ahoy::Event.create!(
      visit: skipped_visit,
      name: "pageview",
      properties: { page: "/landing" },
      time: Time.zone.now.change(usec: 0)
    )

    sign_in(staff_identity)

    get "/admin/analytics/behaviors?period=day&mode=funnels&funnel=Signup+Funnel",
        headers: { "ACCEPT" => "application/json" }

    assert_response :success

    payload = JSON.parse(response.body)
    active = payload.fetch("active")

    assert_in_delta 50.0, active.fetch("conversionRate"), 0.001
    assert_equal 2, active.fetch("enteringVisitors")
    assert_equal 1, active.fetch("neverEnteringVisitors")
    assert_in_delta 66.67, active.fetch("enteringVisitorsPercentage"), 0.01
    assert_in_delta 33.33, active.fetch("neverEnteringVisitorsPercentage"), 0.01

    first_step, second_step = active.fetch("steps")

    assert_equal "View pricing", first_step.fetch("name")
    assert_equal 2, first_step.fetch("visitors")
    assert_in_delta 100.0, first_step.fetch("conversionRate"), 0.001
    assert_in_delta 66.67, first_step.fetch("conversionRateStep"), 0.01
    assert_equal 1, first_step.fetch("dropoff")
    assert_in_delta 33.33, first_step.fetch("dropoffPercentage"), 0.01

    assert_equal "Signup", second_step.fetch("name")
    assert_equal 1, second_step.fetch("visitors")
    assert_in_delta 50.0, second_step.fetch("conversionRate"), 0.001
    assert_in_delta 50.0, second_step.fetch("conversionRateStep"), 0.001
    assert_equal 1, second_step.fetch("dropoff")
    assert_in_delta 50.0, second_step.fetch("dropoffPercentage"), 0.001
  ensure
    Current.reset
  end
end
