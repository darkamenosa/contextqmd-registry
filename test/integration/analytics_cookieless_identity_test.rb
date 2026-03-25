# frozen_string_literal: true

require "test_helper"

class AnalyticsCookielessIdentityTest < ActionDispatch::IntegrationTest
  include ActiveSupport::Testing::TimeHelpers

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
end
