require "test_helper"
require "rails/code_statistics"

class CodeStatisticsTest < ActiveSupport::TestCase
  test "registers frontend directories" do
    assert_includes Rails::CodeStatistics.directories, [ "Frontend", "app/frontend" ]
    assert_includes Rails::CodeStatistics.directories, [ "Frontend tests", "test/frontend" ]
    assert_includes Rails::CodeStatistics.test_types, "Frontend tests"
  end

  test "counts frontend file extensions" do
    assert Rails::CodeStatistics.pattern.match?("component.tsx")
    assert Rails::CodeStatistics.pattern.match?("analytics.mjs")
    assert Rails::CodeStatistics.pattern.match?("component.jsx")
  end
end
