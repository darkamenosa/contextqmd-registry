# frozen_string_literal: true

require "test_helper"

class Analytics::TimeSeriesTest < ActiveSupport::TestCase
  setup do
    Analytics::SiteVisitHourlyRollup.delete_all if Analytics::SiteVisitHourlyRollup.available?
    Analytics::VisitSummary.delete_all if Analytics::VisitSummary.available?
    Ahoy::Event.delete_all
    Ahoy::Visit.delete_all
    Analytics::SiteBoundary.delete_all
    Analytics::Site.delete_all
  end

  test "complex metric series reuses grouped visit rows without changing bucket semantics" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    Analytics::Current.site = site

    range = Time.zone.parse("2026-03-25 00:00:00")..Time.zone.parse("2026-03-25 23:59:59")
    visit_a = create_visit(site:, visitor_token: "a", started_at: Time.zone.parse("2026-03-25 09:00:00"))
    visit_b = create_visit(site:, visitor_token: "b", started_at: Time.zone.parse("2026-03-25 09:15:00"))
    visit_c = create_visit(site:, visitor_token: "c", started_at: Time.zone.parse("2026-03-25 10:00:00"))

    create_pageview(site:, visit: visit_a, time: Time.zone.parse("2026-03-25 09:00:00"), page: "/docs")
    create_pageview(site:, visit: visit_a, time: Time.zone.parse("2026-03-25 09:00:10"), page: "/pricing")
    create_pageview(site:, visit: visit_b, time: Time.zone.parse("2026-03-25 09:15:00"), page: "/docs")
    create_pageview(site:, visit: visit_c, time: Time.zone.parse("2026-03-25 10:00:00"), page: "/pricing")
    Ahoy::Event.create!(
      analytics_site: site,
      visit: visit_c,
      name: "Signup",
      time: Time.zone.parse("2026-03-25 10:00:30"),
      properties: {}
    )

    views = Analytics::TimeSeries.calculate_complex_metric_series(range, "hour", {}, "views_per_visit")
    bounce_rate = Analytics::TimeSeries.calculate_complex_metric_series(range, "hour", {}, "bounce_rate")
    duration = Analytics::TimeSeries.calculate_complex_metric_series(range, "hour", {}, "visit_duration")

    nine_am = Time.zone.parse("2026-03-25 09:00:00").utc
    ten_am = Time.zone.parse("2026-03-25 10:00:00").utc

    assert_equal 1.5, views[nine_am]
    assert_equal 1.0, views[ten_am]
    assert_equal 50.0, bounce_rate[nine_am]
    assert_equal 0.0, bounce_rate[ten_am]
    assert_equal 5.0, duration[nine_am]
    assert_equal 0.0, duration[ten_am]
  end

  test "series_for uses visit hourly rollups for core visit metrics when raw events are gone" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    Analytics::Current.site = site

    range = Time.zone.parse("2026-03-25 00:00:00")..Time.zone.parse("2026-03-25 23:59:59")
    visit_a = create_visit(site:, visitor_token: "a", started_at: Time.zone.parse("2026-03-25 09:00:00"))
    visit_b = create_visit(site:, visitor_token: "b", started_at: Time.zone.parse("2026-03-25 09:15:00"))

    first_pageview = create_pageview(site:, visit: visit_a, time: Time.zone.parse("2026-03-25 09:00:00"), page: "/docs")
    second_pageview = create_pageview(site:, visit: visit_a, time: Time.zone.parse("2026-03-25 09:00:10"), page: "/pricing")
    third_pageview = create_pageview(site:, visit: visit_b, time: Time.zone.parse("2026-03-25 09:15:00"), page: "/docs")

    Analytics::VisitSummary.refresh_visit!(visit_a)
    Analytics::VisitSummary.refresh_visit!(visit_b)
    Analytics::SiteVisitHourlyRollup.refresh_bucket!(site:, bucket_start: Time.zone.parse("2026-03-25 09:00:00"))

    first_pageview.destroy!
    second_pageview.destroy!
    third_pageview.destroy!

    views = Analytics::TimeSeries.series_for(range, "hour", {}, "views_per_visit")
    bounce_rate = Analytics::TimeSeries.series_for(range, "hour", {}, "bounce_rate")
    duration = Analytics::TimeSeries.series_for(range, "hour", {}, "visit_duration")

    nine_am = Time.zone.parse("2026-03-25 09:00:00").utc.iso8601
    views_by_label = views[:labels].zip(views[:values]).to_h
    bounce_rate_by_label = bounce_rate[:labels].zip(bounce_rate[:values]).to_h
    duration_by_label = duration[:labels].zip(duration[:values]).to_h

    assert_equal 1.5, views_by_label[nine_am]
    assert_equal 50.0, bounce_rate_by_label[nine_am]
    assert_equal 5.0, duration_by_label[nine_am]
  end

  test "complex metric series uses visit summaries for filtered queries when raw events are gone" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    Analytics::Current.site = site

    range = Time.zone.parse("2026-03-25 00:00:00")..Time.zone.parse("2026-03-25 23:59:59")
    visit = Ahoy::Visit.create!(
      analytics_site: site,
      visit_token: SecureRandom.hex(16),
      visitor_token: "summary-filter",
      browser: "Chrome",
      started_at: Time.zone.parse("2026-03-25 09:00:00")
    )

    first_pageview = create_pageview(site:, visit:, time: Time.zone.parse("2026-03-25 09:00:00"), page: "/docs")
    second_pageview = create_pageview(site:, visit:, time: Time.zone.parse("2026-03-25 09:00:12"), page: "/pricing")

    Analytics::VisitSummary.refresh_visit!(visit)
    first_pageview.destroy!
    second_pageview.destroy!

    result = Analytics::TimeSeries.calculate_complex_metric_series(range, "hour", { browser: "Chrome" }, "views_per_visit")

    assert_equal 2.0, result[Time.zone.parse("2026-03-25 09:00:00").utc]
  end

  test "series_for keeps minute buckets exact even when hourly rollups exist" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    Analytics::Current.site = site

    visit = create_visit(site:, visitor_token: "minute-visitor", started_at: Time.zone.parse("2026-03-25 09:15:00"))
    create_pageview(site:, visit:, time: Time.zone.parse("2026-03-25 09:15:00"), page: "/docs")

    Analytics::SiteVisitHourlyRollup.refresh_bucket!(site:, bucket_start: Time.zone.parse("2026-03-25 09:00:00"))
    Analytics::SiteEventHourlyRollup.refresh_bucket!(site:, bucket_start: Time.zone.parse("2026-03-25 09:00:00")) if Analytics::SiteEventHourlyRollup.available?

    range = Time.zone.parse("2026-03-25 09:14:00")..Time.zone.parse("2026-03-25 09:16:59")
    visits = Analytics::TimeSeries.series_for(range, "minute", {}, "visits")
    pageviews = Analytics::TimeSeries.series_for(range, "minute", {}, "pageviews")

    visit_values_by_label = visits[:labels].zip(visits[:values]).to_h
    pageview_values_by_label = pageviews[:labels].zip(pageviews[:values]).to_h

    assert_equal 0, visit_values_by_label.fetch(Time.zone.parse("2026-03-25 09:14:00").utc.iso8601)
    assert_equal 1, visit_values_by_label.fetch(Time.zone.parse("2026-03-25 09:15:00").utc.iso8601)
    assert_equal 0, visit_values_by_label.fetch(Time.zone.parse("2026-03-25 09:16:00").utc.iso8601)

    assert_equal 0, pageview_values_by_label.fetch(Time.zone.parse("2026-03-25 09:14:00").utc.iso8601)
    assert_equal 1, pageview_values_by_label.fetch(Time.zone.parse("2026-03-25 09:15:00").utc.iso8601)
    assert_equal 0, pageview_values_by_label.fetch(Time.zone.parse("2026-03-25 09:16:00").utc.iso8601)
  end

  private
    def create_visit(site:, visitor_token:, started_at:)
      Ahoy::Visit.create!(
        analytics_site: site,
        visit_token: SecureRandom.hex(16),
        visitor_token: visitor_token,
        started_at: started_at
      )
    end

    def create_pageview(site:, visit:, time:, page:)
      Ahoy::Event.create!(
        analytics_site: site,
        visit: visit,
        name: "pageview",
        time: time,
        properties: { page: page }
      )
    end
end
