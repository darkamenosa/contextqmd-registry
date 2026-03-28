# frozen_string_literal: true

require "test_helper"

class Analytics::PaginationTest < ActiveSupport::TestCase
  test "paginate_names returns one page and has_more" do
    names, has_more = Analytics::Pagination.paginate_names(%w[a b c], limit: 2, page: 1)

    assert_equal %w[a b], names
    assert_equal true, has_more
  end

  test "list_response keeps metric labels in meta" do
    payload = Analytics::Pagination.list_response(
      results: [ { name: "Organic" } ],
      metrics: { visitors: 10 },
      has_more: true,
      metric_labels: { visitors: "Visitors" }
    )

    assert_equal true, payload.dig(:meta, :has_more)
    assert_equal "Visitors", payload.dig(:meta, :metric_labels, :visitors)
  end
end
