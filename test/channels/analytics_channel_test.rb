# frozen_string_literal: true

require "test_helper"

class AnalyticsChannelTest < ActionCable::Channel::TestCase
  setup do
    @staff_identity, = create_tenant(
      email: "staff-channel-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Channel"
    )
    @staff_identity.update!(staff: true)

    stub_connection current_user: @staff_identity
  end

  test "subscribes to the explicit site stream when site_id is provided" do
    site = Analytics::Site.create!(
      name: "Docs",
      canonical_hostname: "docs.example.test",
      time_zone: "UTC"
    )

    subscribe(subscription_token: Analytics::LiveState.subscription_token(site: site))

    assert subscription.confirmed?
    assert_has_stream "analytics:#{site.public_id}"
  end

  test "subscribing transmits the current scoped live payload" do
    site = Analytics::Site.create!(
      name: "Docs",
      canonical_hostname: "docs.example.test",
      time_zone: "UTC"
    )
    payload = { "currentVisitors" => 3, "recentEvents" => [] }

    with_stubbed_singleton_method(Analytics::LiveState, :payload_for_site, payload) do
      subscribe(subscription_token: Analytics::LiveState.subscription_token(site: site))

      assert subscription.confirmed?
      assert_equal payload, transmissions.last
    end
  end

  test "rejects subscriptions without a valid live subscription token" do
    subscribe(subscription_token: "invalid-token")

    refute subscription.confirmed?
    assert_no_streams
  end
end
