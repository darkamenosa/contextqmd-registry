# frozen_string_literal: true

require "test_helper"

class AnalyticsCookielessIdentityTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers
  include TenantTestHelper

  BROWSER_HEADERS = {
    "HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36",
    "REMOTE_ADDR" => "203.0.113.42"
  }.freeze

  setup do
    Ahoy::Event.delete_all
    Ahoy::Visit.delete_all
  end

  test "cookieless event ingestion reuses the recent server-side visit without client tokens" do
    assert_difference -> { Ahoy::Visit.count }, +1 do
      assert_difference -> { Ahoy::Event.count }, +1 do
        get root_path, headers: BROWSER_HEADERS
      end
    end

    assert_response :success
    visit = Ahoy::Visit.order(:id).last

    assert_no_difference -> { Ahoy::Visit.count } do
      assert_difference -> { Ahoy::Event.count }, +1 do
        post "/ahoy/events",
          params: {
            events: [
              {
                name: "engagement",
                properties: {
                  page: "/",
                  url: root_url,
                  title: "Home",
                  referrer: "",
                  screen_size: "1440x900"
                },
                time: Time.current.iso8601
              }
            ]
          },
          as: :json,
          headers: BROWSER_HEADERS
      end
    end

    assert_response :success
    assert_equal visit.id, Ahoy::Event.order(:id).last.visit_id
    assert_equal visit.id, Ahoy::Visit.order(:id).last.id
  end

  test "cookieless event ingestion ignores spoofed client tokens" do
    get root_path, headers: BROWSER_HEADERS
    visit = Ahoy::Visit.order(:id).last

    assert_no_difference -> { Ahoy::Visit.count } do
      assert_difference -> { Ahoy::Event.count }, +1 do
        post "/ahoy/events",
          params: {
            visit_token: SecureRandom.uuid,
            visitor_token: SecureRandom.uuid,
            events: [
              {
                name: "engagement",
                properties: {
                  page: "/",
                  url: root_url,
                  title: "Home",
                  referrer: "",
                  screen_size: "1440x900"
                },
                time: Time.current.iso8601
              }
            ]
          },
          as: :json,
          headers: BROWSER_HEADERS
      end
    end

    assert_response :success
    assert_equal visit.id, Ahoy::Event.order(:id).last.visit_id
  end

  test "cookieless event ingestion reuses the recent visit across daily rotation" do
    visit = nil

    travel_to Time.utc(2026, 3, 25, 23, 59, 50) do
      get root_path, headers: BROWSER_HEADERS
      visit = Ahoy::Visit.order(:id).last
    end

    travel_to Time.utc(2026, 3, 26, 0, 0, 10) do
      assert_no_difference -> { Ahoy::Visit.count } do
        assert_difference -> { Ahoy::Event.count }, +1 do
          post "/ahoy/events",
            params: {
              events: [
                {
                  name: "engagement",
                  properties: {
                    page: "/",
                    url: root_url,
                    title: "Home",
                    referrer: "",
                    screen_size: "1440x900"
                  },
                  time: Time.current.iso8601
                }
              ]
            },
            as: :json,
            headers: BROWSER_HEADERS
        end
      end
    end

    assert_response :success
    assert_equal visit.id, Ahoy::Event.order(:id).last.visit_id
    assert_equal visit.id, Ahoy::Visit.order(:id).last.id
  end

  test "cookieless engagement does not create a new visit after the session window expires" do
    travel_to Time.utc(2026, 3, 25, 10, 0, 0) do
      get root_path, headers: BROWSER_HEADERS
    end

    expired_visit = Ahoy::Visit.order(:id).last

    travel_to Time.utc(2026, 3, 25, 10, 31, 0) do
      assert_no_difference -> { Ahoy::Visit.count } do
        assert_no_difference -> { Ahoy::Event.count } do
          post "/ahoy/events",
            params: {
              events: [
                {
                  name: "engagement",
                  properties: {
                    page: "/",
                    url: root_url,
                    title: "Home",
                    referrer: "",
                    screen_size: "1440x900"
                  },
                  time: Time.current.iso8601
                }
              ]
            },
            as: :json,
            headers: BROWSER_HEADERS
        end
      end
    end

    assert_response :success
    assert_equal expired_visit.id, Ahoy::Visit.order(:id).last.id
  end

  test "logout forces a new anonymous visit on next tracked page" do
    identity, = create_tenant(
      email: "analytics-logout-#{SecureRandom.hex(4)}@example.com",
      name: "Analytics Logout"
    )

    get root_path, headers: BROWSER_HEADERS
    initial_visit = Ahoy::Visit.order(:id).last

    assert_no_difference -> { Ahoy::Visit.count } do
      post identity_session_path, params: {
        identity: {
          email: identity.email,
          password: "password123"
        }
      }, headers: BROWSER_HEADERS
    end

    assert_redirected_to app_path
    assert_equal identity.id, initial_visit.reload.user_id

    assert_no_difference -> { Ahoy::Visit.count } do
      delete destroy_identity_session_path, headers: BROWSER_HEADERS
    end

    assert_redirected_to root_path

    assert_difference -> { Ahoy::Visit.count }, +1 do
      assert_difference -> { Ahoy::Event.count }, +1 do
        get root_path, headers: BROWSER_HEADERS
      end
    end

    next_visit = Ahoy::Visit.order(:id).last
    assert_not_equal initial_visit.id, next_visit.id
    assert_nil next_visit.user_id
    assert_equal initial_visit.visitor_token, next_visit.visitor_token
  end

  test "signing in as a different user after logout forces a new visit" do
    first_identity, = create_tenant(
      email: "analytics-switch-a-#{SecureRandom.hex(4)}@example.com",
      name: "Analytics Switch A"
    )
    second_identity, = create_tenant(
      email: "analytics-switch-b-#{SecureRandom.hex(4)}@example.com",
      name: "Analytics Switch B"
    )

    get root_path, headers: BROWSER_HEADERS
    initial_visit = Ahoy::Visit.order(:id).last

    post identity_session_path, params: {
      identity: {
        email: first_identity.email,
        password: "password123"
      }
    }, headers: BROWSER_HEADERS

    assert_redirected_to app_path
    assert_equal first_identity.id, initial_visit.reload.user_id

    delete destroy_identity_session_path, headers: BROWSER_HEADERS

    assert_redirected_to root_path

    assert_no_difference -> { Ahoy::Visit.count } do
      post identity_session_path, params: {
        identity: {
          email: second_identity.email,
          password: "password123"
        }
      }, headers: BROWSER_HEADERS
    end

    assert_redirected_to app_path
    assert_equal first_identity.id, initial_visit.reload.user_id
    assert_equal true, request.session["analytics.force_new_visit"]

    assert_difference -> { Ahoy::Visit.count }, +1 do
      assert_difference -> { Ahoy::Event.count }, +1 do
        get about_path, headers: BROWSER_HEADERS
      end
    end

    next_visit = Ahoy::Visit.order(:id).last
    assert_not_equal initial_visit.id, next_visit.id
    assert_equal second_identity.id, next_visit.user_id
    assert_equal initial_visit.visitor_token, next_visit.visitor_token
  end
end
