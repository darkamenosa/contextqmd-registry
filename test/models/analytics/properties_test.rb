# frozen_string_literal: true

require "test_helper"

class Analytics::PropertiesTest < ActiveSupport::TestCase
  test "filter helpers recognize analytics property filters" do
    assert_equal true, Analytics::Properties.filter_key?("prop:plan")
    assert_equal false, Analytics::Properties.filter_key?("page")
    assert_equal "plan", Analytics::Properties.filter_name("prop:plan")
  end
end
