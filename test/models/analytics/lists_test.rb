# frozen_string_literal: true

require "test_helper"

class Analytics::ListsTest < ActiveSupport::TestCase
  test "normalize_strings strips blanks, de-duplicates, and sorts" do
    values = [ "  beta ", "", nil, "alpha", "beta", "  " ]

    assert_equal [ "alpha", "beta" ], Analytics::Lists.normalize_strings(values)
  end
end
