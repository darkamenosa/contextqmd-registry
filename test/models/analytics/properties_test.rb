# frozen_string_literal: true

require "test_helper"

class Analytics::PropertiesTest < ActiveSupport::TestCase
  setup do
    Analytics::AllowedEventProperty.delete_all if defined?(Analytics::AllowedEventProperty)
    Analytics::Setting.delete_all
    Analytics::Site.delete_all
  end

  test "filter helpers recognize analytics property filters" do
    assert_equal true, Analytics::Properties.filter_key?("prop:plan")
    assert_equal false, Analytics::Properties.filter_key?("page")
    assert_equal "plan", Analytics::Properties.filter_name("prop:plan")
  end

  test "configured keys come from typed site-owned properties" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    Analytics::AllowedEventProperty.sync_keys!(%w[plan source], site: site)

    ::Analytics::Current.site = site

    assert_equal %w[plan source], Analytics::Properties.configured_keys
    assert_equal true, Analytics::Properties.managed_keys?
  ensure
    Current.reset
  end
end
