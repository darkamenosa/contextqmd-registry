# frozen_string_literal: true

require "test_helper"

class Analytics::SearchTest < ActiveSupport::TestCase
  test "contains_pattern escapes sql wildcards and lowercases input" do
    assert_equal "%100\\%\\_match%", Analytics::Search.contains_pattern("100%_MATCH")
  end
end
