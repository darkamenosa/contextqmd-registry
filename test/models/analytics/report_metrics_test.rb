# frozen_string_literal: true

require "test_helper"

class Analytics::ReportMetricsTest < ActiveSupport::TestCase
  test "percentage_total_visitors returns one when the relation is empty" do
    assert_equal 1, Analytics::ReportMetrics.percentage_total_visitors(Ahoy::Visit.none)
  end
end
