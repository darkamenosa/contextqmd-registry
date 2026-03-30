# frozen_string_literal: true

require "test_helper"

class AnalyticsProfileKeyTest < ActiveSupport::TestCase
  setup do
    AnalyticsProfileKey.delete_all
    AnalyticsProfile.delete_all
    Analytics::Site.delete_all
  end

  test "normalize_strong_keys accepts a hash of keys" do
    normalized_keys = AnalyticsProfileKey.normalize_strong_keys(
      identity_id: 123,
      email_hash: "abc"
    )

    assert_equal(
      [
        { kind: "identity_id", value: "123" },
        { kind: "email_hash", value: "abc" }
      ],
      normalized_keys
    )
  end

  test "normalize_strong_keys accepts an array of normalized keys" do
    normalized_keys = AnalyticsProfileKey.normalize_strong_keys(
      [
        { kind: :identity_id, value: 123 },
        { kind: "email_hash", value: "abc" }
      ]
    )

    assert_equal(
      [
        { kind: "identity_id", value: "123" },
        { kind: "email_hash", value: "abc" }
      ],
      normalized_keys
    )
  end

  test "matching_profiles stays scoped to the current analytics site" do
    site_a = Analytics::Site.create!(name: "Docs", canonical_hostname: "docs.example.test")
    site_b = Analytics::Site.create!(name: "Blog", canonical_hostname: "blog.example.test")

    profile_a = AnalyticsProfile.create!(
      analytics_site: site_a,
      status: AnalyticsProfile::STATUS_IDENTIFIED,
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )
    AnalyticsProfileKey.create!(
      analytics_profile: profile_a,
      analytics_site: site_a,
      kind: "identity_id",
      value: "123",
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )

    profile_b = AnalyticsProfile.create!(
      analytics_site: site_b,
      status: AnalyticsProfile::STATUS_IDENTIFIED,
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )
    AnalyticsProfileKey.create!(
      analytics_profile: profile_b,
      analytics_site: site_b,
      kind: "identity_id",
      value: "123",
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )

    assert_equal [ profile_a.id ], AnalyticsProfileKey.matching_profiles([ { kind: "identity_id", value: "123" } ], site: site_a).pluck(:id)
    assert_equal [ profile_b.id ], AnalyticsProfileKey.matching_profiles([ { kind: "identity_id", value: "123" } ], site: site_b).pluck(:id)
  end
end
