# frozen_string_literal: true

require "test_helper"

class AnalyticsBootstrapTest < ActionDispatch::IntegrationTest
  MODERN_BROWSER_HEADERS = {
    "HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/146.0.0.0 Safari/537.36"
  }.freeze

  test "layout exposes analytics runtime config from rails settings" do
    with_server_visits(true) do
      assert_difference -> { Ahoy::Visit.count }, +1 do
        assert_difference -> { Ahoy::Event.count }, +1 do
          get root_path, headers: MODERN_BROWSER_HEADERS
        end
      end

      assert_response :success
      assert_includes response.body, "\"visitDurationMinutes\":30"
      assert_includes response.body, "\"trackVisits\":false"
      assert_includes response.body, "\"useBeaconForEvents\":false"
      assert_includes response.body, "\"useCookies\":false"
      assert_includes response.body, "\"initialPageviewTracked\":true"
      assert_includes response.body, "\"initialPageKey\":\"/\""
      refute_includes response.body, "meta name=\"ahoy-visit\""
      refute_includes response.body, "meta name=\"ahoy-visitor\""
    end
  end

  test "server bootstrap stays off when server-side visits are disabled" do
    with_server_visits(false) do
      assert_no_difference -> { Ahoy::Visit.count } do
        assert_no_difference -> { Ahoy::Event.count } do
          get root_path, headers: MODERN_BROWSER_HEADERS
        end
      end

      assert_response :success
      assert_includes response.body, "\"trackVisits\":false"
      assert_includes response.body, "\"initialPageviewTracked\":false"
      refute_includes response.body, "meta name=\"ahoy-visit\""
      refute_includes response.body, "meta name=\"ahoy-visitor\""
    end
  end

  test "auth pages bootstrap and track analytics" do
    with_server_visits(true) do
      assert_difference -> { Ahoy::Visit.count }, +1 do
        assert_difference -> { Ahoy::Event.count }, +1 do
          get "/login", headers: MODERN_BROWSER_HEADERS
        end
      end

      assert_response :success
      assert_includes response.body, "\"initialPageviewTracked\":true"
      assert_includes response.body, "\"initialPageKey\":\"/login\""
      refute_includes response.body, "meta name=\"ahoy-visit\""
      refute_includes response.body, "meta name=\"ahoy-visitor\""
    end
  end

  test "head requests do not bootstrap or track analytics" do
    with_server_visits(true) do
      assert_no_difference -> { Ahoy::Visit.count } do
        assert_no_difference -> { Ahoy::Event.count } do
          head root_path, headers: MODERN_BROWSER_HEADERS
        end
      end

      assert_response :success
    end
  end

  test "prefetch requests do not bootstrap or track analytics" do
    with_server_visits(true) do
      assert_no_difference -> { Ahoy::Visit.count } do
        assert_no_difference -> { Ahoy::Event.count } do
          get root_path,
            headers: MODERN_BROWSER_HEADERS.merge(
              "Purpose" => "prefetch",
              "Sec-Purpose" => "prefetch;prerender"
            )
        end
      end

      assert_response :success
      assert_includes response.body, "\"initialPageviewTracked\":false"
      refute_includes response.body, "meta name=\"ahoy-visit\""
      refute_includes response.body, "meta name=\"ahoy-visitor\""
    end
  end

  private
    def with_server_visits(enabled)
      original = Rails.configuration.x.analytics.server_visits
      Rails.configuration.x.analytics.server_visits = enabled
      yield
    ensure
      Rails.configuration.x.analytics.server_visits = original
    end
end
