# frozen_string_literal: true

require "test_helper"

class Analytics::SourceResolverTest < ActiveSupport::TestCase
  test "resolves plausible-style paid social aliases" do
    resolution = Analytics::SourceResolver.resolve(
      utm_source: "fbads",
      utm_medium: "cpc"
    )

    assert_equal "Facebook", resolution.source_label
    assert_equal "social", resolution.source_kind
    assert_equal "Paid Social", resolution.source_channel
    assert_equal "facebook.com", resolution.source_favicon_domain
    assert_equal true, resolution.source_paid
    assert_equal "utm-facebook-fbads", resolution.source_rule_id
  end

  test "resolves x short alias to twitter" do
    resolution = Analytics::SourceResolver.resolve(
      utm_source: "x"
    )

    assert_equal "Twitter", resolution.source_label
    assert_equal "social", resolution.source_kind
    assert_equal "Organic Social", resolution.source_channel
    assert_equal "x.com", resolution.source_favicon_domain
    assert_equal "utm-x", resolution.source_rule_id
  end

  test "resolves wikipedia mobile subdomains as one source" do
    resolution = Analytics::SourceResolver.resolve(
      referring_domain: "en.m.wikipedia.org"
    )

    assert_equal "Wikipedia", resolution.source_label
    assert_equal "referral", resolution.source_kind
    assert_equal "Referral", resolution.source_channel
    assert_equal "en.wikipedia.org", resolution.source_favicon_domain
  end

  test "resolves plausible custom source domains" do
    {
      "ntp.msn.com" => "Bing",
      "ya.ru" => "Yandex",
      "t.me" => "Telegram",
      "android-app://com.reddit.frontpage" => "Reddit",
      "teams.microsoft.com" => "Microsoft Teams"
    }.each do |raw_value, expected_label|
      resolution = Analytics::SourceResolver.resolve(referring_domain: raw_value)

      assert_equal expected_label, resolution.source_label
    end
  end

  test "treats same-site referrals as direct" do
    resolution = Analytics::SourceResolver.resolve(
      referrer: "https://docs.example.com/pricing",
      referring_domain: "docs.example.com",
      hostname: "docs.example.com"
    )

    assert_equal "Direct / None", resolution.source_label
    assert_equal "direct", resolution.source_kind
    assert_equal "Direct", resolution.source_channel
  end
end
