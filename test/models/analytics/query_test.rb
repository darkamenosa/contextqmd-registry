# frozen_string_literal: true

require "test_helper"

class Analytics::QueryTest < ActiveSupport::TestCase
  test "wrap normalizes keys and preserves nested query access" do
    query = Analytics::Query.wrap(
      "period" => "day",
      "filters" => { "page" => "/pricing" },
      "advanced_filters" => [ [ "contains", "page", "/pricing" ] ],
      "order_by" => [ [ "visitors", "desc" ] ]
    )

    assert_equal "day", query[:period]
    assert_equal({ "page" => "/pricing" }, query.filters)
    assert_equal "/pricing", query.dig(:filters, :page)
    assert_equal "/pricing", query[:filters]["page"]
    assert_equal [ [ "contains", "page", "/pricing" ] ], query.advanced_filters
    assert_equal "day", query.time_range_key
    assert_equal [ [ :eq, :page, "/pricing" ], [ :contains, :page, "/pricing" ] ], query.filter_clauses
    assert_equal [ [ :visitors, :desc ] ], query.order_by
  end

  test "merge returns a new analytics query" do
    query = Analytics::Query.wrap(period: "day", filters: { page: "/" })
    merged = query.merge(mode: "visitors", filters: { page: "/pricing" })

    assert_instance_of Analytics::Query, merged
    assert_equal "day", query[:period]
    assert_equal "/", query.dig(:filters, :page)
    assert_equal "visitors", merged[:mode]
    assert_equal "/pricing", merged.dig(:filters, :page)
    assert_equal [ [ :eq, :page, "/pricing" ] ], merged.filter_clauses
  end

  test "from_ui_params derives semantic analytics fields" do
    query = Analytics::Query.from_ui_params(
      {
        period: "custom",
        from: "2026-03-01",
        to: "2026-03-15",
        mode: "pages",
        filters: { page: "/pricing" },
        advanced_filters: [ [ "contains", "source", "google" ] ]
      },
      dataset: :pages,
      order_by: [ [ "visitors", "desc" ] ],
      limit: 25,
      page: 3
    )

    assert_equal :pages, query.dataset
    assert_equal "custom", query.time_range[:key]
    assert_equal "2026-03-01", query.time_range[:from]
    assert_equal "2026-03-15", query.time_range[:to]
    assert_equal "pages", query.mode
    assert_equal [ [ :visitors, :desc ] ], query.order_by
    assert_equal 25, query.limit
    assert_equal 50, query.offset
    assert_equal [
      [ :eq, :page, "/pricing" ],
      [ :contains, :source, "google" ]
    ], query.filter_clauses
  end

  test "comparison filters normalize names and codes" do
    query = Analytics::Query.wrap(
      comparison_names: [ " Vietnam ", "", nil ],
      comparison_codes: [ " us ", "", nil ]
    )

    assert_equal [ "Vietnam" ], query.comparison_filter_names
    assert_equal [ "US" ], query.comparison_filter_codes
  end

  test "without_goal_or_properties removes goal and property filters" do
    query = Analytics::Query.wrap(
      filters: { goal: "Signup", page: "/pricing", "prop:plan" => "pro" },
      advanced_filters: [
        [ "is", "goal", "Signup" ],
        [ "contains", "page", "/pricing" ],
        [ "is", "prop:plan", "pro" ]
      ]
    )

    cleaned = query.without_goal_or_properties(property_filter: ->(key) { key.to_s.start_with?("prop:") })

    assert_equal({ "page" => "/pricing" }, cleaned.filters)
    assert_equal [ [ "contains", "page", "/pricing" ] ], cleaned.advanced_filters
  end

  test "without_goal removes only goal filters" do
    query = Analytics::Query.wrap(
      filters: { goal: "Signup", page: "/pricing", "prop:plan" => "pro" },
      advanced_filters: [
        [ "is", "goal", "Signup" ],
        [ "contains", "page", "/pricing" ],
        [ "is", "prop:plan", "pro" ]
      ]
    )

    cleaned = query.without_goal

    assert_equal({ "page" => "/pricing", "prop:plan" => "pro" }, cleaned.filters)
    assert_equal [ [ "contains", "page", "/pricing" ] ], cleaned.advanced_filters
  end

  test "semantic helpers derive legacy filters and comparison values from filter_clauses" do
    query = Analytics::Query.wrap(
      filter_clauses: [
        [ :eq, :page, "/pricing" ],
        [ :contains, :source, "google" ],
        [ :comparison_name, :name, "Vietnam" ],
        [ :comparison_code, :code, "us" ]
      ],
      time_range: { key: "day", comparison: "previous_period" },
      options: { mode: "sources", metric: "visitors", interval: "day", with_imported: true }
    )

    assert_equal({ "page" => "/pricing" }, query.filters)
    assert_equal [ [ "contains", "source", "google" ] ], query.advanced_filters
    assert_equal [ "Vietnam" ], query.comparison_filter_names
    assert_equal [ "US" ], query.comparison_filter_codes
    assert_equal "sources", query.mode
    assert_equal "visitors", query.metric
    assert_equal "day", query.interval
    assert_equal "previous_period", query.comparison
    assert_equal true, query.with_imported?
    assert_equal "/pricing", query.filter_value(:page)
    assert_equal [ "page", "source" ], query.filter_dimensions
  end

  test "with_filter replaces an equality filter without disturbing others" do
    query = Analytics::Query.wrap(
      filter_clauses: [
        [ :eq, :goal, "Signup" ],
        [ :contains, :page, "/pricing" ]
      ]
    )

    updated = query.with_filter(:goal, "Purchase")

    assert_equal "Purchase", updated.filter_value(:goal)
    assert_equal [ [ "contains", "page", "/pricing" ] ], updated.advanced_filters
  end
end
