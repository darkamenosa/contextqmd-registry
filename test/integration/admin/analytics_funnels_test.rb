# frozen_string_literal: true

require "test_helper"

class Admin::AnalyticsFunnelsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    Analytics::Funnel.delete_all
    Analytics::SiteBoundary.delete_all
    Analytics::Site.delete_all
    Analytics::Bootstrap.ensure_default_site!(host: "localhost")
  end

  test "funnels controller persists typed funnel steps" do
    staff_identity, = create_tenant(
      email: "staff-analytics-funnels-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Analytics Funnels"
    )
    staff_identity.update!(staff: true)
    sign_in(staff_identity)

    post funnels_path,
      params: {
        funnel: {
          name: "Signup Funnel",
          steps: [
            { name: "Visit pricing", type: "page_visit", match: "starts_with", value: "/pricing" },
            { name: "Signup", type: "goal", match: "completes", goal_key: "signup" }
          ]
        }
      },
      as: :json

    assert_response :created

    funnel = Analytics::Funnel.find_by!(name: "Signup Funnel")
    assert_equal [
      { "name" => "Visit pricing", "type" => "page_visit", "match" => "starts_with", "value" => "/pricing" },
      { "name" => "Signup", "type" => "goal", "match" => "completes", "goal_key" => "signup" }
    ], funnel.steps
  ensure
    Current.reset
  end

  test "funnels controller normalizes legacy string and legacy typed steps" do
    staff_identity, = create_tenant(
      email: "staff-analytics-funnels-legacy-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Analytics Funnels Legacy"
    )
    staff_identity.update!(staff: true)
    sign_in(staff_identity)

    post funnels_path,
      params: {
        funnel: {
          name: "Legacy Funnel",
          steps: [
            "/pricing",
            { name: "Signup", type: "event", match: "equals", value: "signup" }
          ]
        }
      },
      as: :json

    assert_response :created

    funnel = Analytics::Funnel.find_by!(name: "Legacy Funnel")
    assert_equal [
      { "name" => "/pricing", "type" => "page_visit", "match" => "equals", "value" => "/pricing" },
      { "name" => "Signup", "type" => "goal", "match" => "completes", "goal_key" => "signup" }
    ], funnel.steps
  ensure
    Current.reset
  end

  private
    def funnels_path
      "/admin/analytics/sites/#{Analytics::Site.sole_active.public_id}/funnels"
    end
end
