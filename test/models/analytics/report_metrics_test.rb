# frozen_string_literal: true

require "test_helper"

class Analytics::ReportMetricsTest < ActiveSupport::TestCase
  setup do
    Analytics::VisitSummary.delete_all if Analytics::VisitSummary.available?
    Ahoy::Event.delete_all
    Ahoy::Visit.delete_all
    Analytics::SiteBoundary.delete_all
    Analytics::Site.delete_all
  end

  test "percentage_total_visitors returns one when the relation is empty" do
    assert_equal 1, Analytics::ReportMetrics.percentage_total_visitors(Ahoy::Visit.none)
  end

  test "calculate_group_metrics keeps bounce and duration semantics" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    Analytics::Current.site = site

    range = Time.zone.parse("2026-03-25 00:00:00")..Time.zone.parse("2026-03-25 23:59:59")
    docs_visit = create_visit(site:, visitor_token: "docs", started_at: Time.zone.parse("2026-03-25 09:00:00"))
    bounce_visit = create_visit(site:, visitor_token: "bounce", started_at: Time.zone.parse("2026-03-25 09:15:00"))
    engaged_visit = create_visit(site:, visitor_token: "engaged", started_at: Time.zone.parse("2026-03-25 10:00:00"))

    create_pageview(site:, visit: docs_visit, time: Time.zone.parse("2026-03-25 09:00:00"), page: "/docs")
    create_pageview(site:, visit: docs_visit, time: Time.zone.parse("2026-03-25 09:00:15"), page: "/pricing")
    create_pageview(site:, visit: bounce_visit, time: Time.zone.parse("2026-03-25 09:15:00"), page: "/docs")
    create_pageview(site:, visit: engaged_visit, time: Time.zone.parse("2026-03-25 10:00:00"), page: "/pricing")
    Ahoy::Event.create!(
      analytics_site: site,
      visit: engaged_visit,
      name: "Signup",
      time: Time.zone.parse("2026-03-25 10:00:30"),
      properties: {}
    )

    metrics = Analytics::ReportMetrics.calculate_group_metrics(
      {
        "Docs" => [ docs_visit.id, bounce_visit.id ],
        "Pricing" => [ engaged_visit.id ]
      },
      range,
      {}
    )

    assert_equal 50.0, metrics.dig("Docs", :bounce_rate)
    assert_equal 7.5, metrics.dig("Docs", :visit_duration)
    assert_equal 0.0, metrics.dig("Pricing", :bounce_rate)
    assert_equal 0.0, metrics.dig("Pricing", :visit_duration)
  end

  test "visit_metrics and group_metrics use visit page summaries when pageviews are gone" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    Analytics::Current.site = site

    range = Time.zone.parse("2026-03-25 00:00:00")..Time.zone.parse("2026-03-25 23:59:59")
    visit = create_visit(site:, visitor_token: "summary-only", started_at: Time.zone.parse("2026-03-25 09:00:00"))

    first_pageview = create_pageview(site:, visit:, time: Time.zone.parse("2026-03-25 09:00:00"), page: "/docs")
    second_pageview = create_pageview(site:, visit:, time: Time.zone.parse("2026-03-25 09:10:00"), page: "/pricing")
    Analytics::VisitSummary.refresh_visit!(visit)

    first_pageview.destroy!
    second_pageview.destroy!

    visits_scope = Analytics::VisitScope.visits(range, {})
    metrics = Analytics::ReportMetrics.visit_metrics(visits_scope, Analytics::VisitScope.pageviews(range, {}))
    grouped = Analytics::ReportMetrics.calculate_group_metrics({ "Docs" => [ visit.id ] }, range, {})

    assert_equal 2, metrics[:pageviews]
    assert_equal 2.0, metrics[:pageviews_per_visit]
    assert_equal 600.0, metrics[:average_duration]
    assert_equal 0.0, metrics[:bounce_rate]
    assert_equal 0.0, grouped.dig("Docs", :bounce_rate)
    assert_equal 600.0, grouped.dig("Docs", :visit_duration)
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
