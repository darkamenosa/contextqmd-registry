# frozen_string_literal: true

require "test_helper"

class Admin::AnalyticsSettingsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    AnalyticsSetting.delete_all
    Goal.delete_all
    Funnel.delete_all
  end

  test "settings api persists goal definitions and allowed event props" do
    staff_identity, = create_tenant(
      email: "staff-analytics-settings-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Analytics Settings"
    )
    staff_identity.update!(staff: true)

    sign_in(staff_identity)

    patch "/admin/analytics/settings",
      params: {
        settings: {
          gsc_configured: true,
          goal_definitions: [
            {
              display_name: " Signup ",
              event_name: "signup",
              custom_props: { plan: "Pro" }
            },
            {
              display_name: "Visit Pricing",
              page_path: "pricing",
              scroll_threshold: -1,
              custom_props: {}
            }
          ],
          allowed_event_props: [ " plan ", "source", "" ]
        }
      },
      as: :json

    assert_response :no_content

    get "/admin/analytics/settings", headers: { "ACCEPT" => "application/json" }

    assert_response :success

    payload = JSON.parse(response.body)
    settings = payload.fetch("settings")
    assert_equal true, settings.fetch("gscConfigured")
    assert_equal [ "Signup", "Visit Pricing" ], settings.fetch("goals")
    assert_equal 2, settings.fetch("goalDefinitions").length
    assert_equal [ "Signup", "Visit Pricing" ], Goal.order(:display_name).pluck(:display_name)
    assert_equal [ "signup", nil ], Goal.order(:display_name).pluck(:event_name)
    assert_equal [ nil, "/pricing" ], Goal.order(:display_name).pluck(:page_path)
    assert_equal [ "plan", "source" ], settings.fetch("allowedEventProps")
  ensure
    Current.reset
  end

  test "settings api allows multiple event goals with different property matches" do
    staff_identity, = create_tenant(
      email: "staff-analytics-settings-props-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Analytics Settings Props"
    )
    staff_identity.update!(staff: true)

    sign_in(staff_identity)

    patch "/admin/analytics/settings",
      params: {
        settings: {
          goal_definitions: [
            {
              display_name: "Signup Pro",
              event_name: "signup",
              custom_props: { plan: "Pro" }
            },
            {
              display_name: "Signup Free",
              event_name: "signup",
              custom_props: { plan: "Free" }
            }
          ]
        }
      },
      as: :json

    assert_response :no_content
    assert_equal 2, Goal.count
    assert_equal [ { "plan" => "Free" }, { "plan" => "Pro" } ], Goal.order(:display_name).pluck(:custom_props)
  ensure
    Current.reset
  end
end
