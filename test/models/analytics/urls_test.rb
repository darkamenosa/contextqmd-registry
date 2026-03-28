# frozen_string_literal: true

require "test_helper"

class Analytics::UrlsTest < ActiveSupport::TestCase
  test "normalized_path_and_query keeps pathname and query" do
    assert_equal "/docs?tab=api", Analytics::Urls.normalized_path_and_query("https://example.com/docs?tab=api")
  end

  test "normalized_path_only strips the query string" do
    assert_equal "/docs", Analytics::Urls.normalized_path_only("/docs?tab=api")
  end
end
