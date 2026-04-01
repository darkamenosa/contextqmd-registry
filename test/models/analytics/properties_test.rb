# frozen_string_literal: true

require "test_helper"

class Analytics::PropertiesTest < ActiveSupport::TestCase
  setup do
    Ahoy::Event.delete_all
    Ahoy::Visit.delete_all
    Analytics::AllowedEventProperty.delete_all if defined?(Analytics::AllowedEventProperty)
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

  test "available keys include discovered event properties when no managed keys exist" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      analytics_site: site,
      started_at: Time.zone.now.change(usec: 0)
    )

    Ahoy::Event.create!(
      visit: visit,
      analytics_site: site,
      name: "signup",
      properties: { plan: "Pro", source: "Ads", page: "/pricing" },
      time: Time.zone.now.change(usec: 0)
    )

    ::Analytics::Current.site = site

    assert_equal %w[plan source], Analytics::Properties.available_keys
    assert_equal true, Analytics::Properties.available?
  ensure
    Current.reset
  end

  test "available keys keep configured keys ahead of discovered keys" do
    site = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    visit = Ahoy::Visit.create!(
      visit_token: SecureRandom.hex(16),
      visitor_token: SecureRandom.hex(16),
      analytics_site: site,
      started_at: Time.zone.now.change(usec: 0)
    )

    Ahoy::Event.create!(
      visit: visit,
      analytics_site: site,
      name: "signup",
      properties: { plan: "Pro", source: "Ads" },
      time: Time.zone.now.change(usec: 0)
    )
    Analytics::AllowedEventProperty.sync_keys!(%w[source], site: site)

    ::Analytics::Current.site = site

    assert_equal %w[source plan], Analytics::Properties.available_keys
  ensure
    Current.reset
  end
end
