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
      assert_includes response.body, "\"version\":1"
      assert_includes response.body, "\"transport\":{\"eventsEndpoint\":\"/a/e\"}"
      assert_includes response.body, "\"site\":{\"websiteId\":"
      assert_includes response.body, "\"token\":"
      assert_includes response.body, "\"tracking\":{\"hashBasedRouting\":false,\"initialPageviewTracked\":true"
      assert_includes response.body, %(<script src="/a/t.js" defer="defer"></script>)
      refute_includes response.body, "vite/assets/analytics"
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
      assert_includes response.body, "\"version\":1"
      assert_includes response.body, "\"tracking\":{\"hashBasedRouting\":false,\"initialPageviewTracked\":false"
      refute_includes response.body, "meta name=\"ahoy-visit\""
      refute_includes response.body, "meta name=\"ahoy-visitor\""
    end
  end

  test "auth pages bootstrap analytics for hybrid first pageviews" do
    with_server_visits(true) do
      assert_difference -> { Ahoy::Visit.count }, +1 do
        assert_difference -> { Ahoy::Event.count }, +1 do
          get "/login", headers: MODERN_BROWSER_HEADERS
        end
      end

      assert_response :success
      assert_includes response.body, "\"site\":{\"websiteId\":"
      assert_includes response.body, "\"token\":"
      assert_includes response.body, "\"tracking\":{\"hashBasedRouting\":false,\"initialPageviewTracked\":true"
      refute_includes response.body, "meta name=\"ahoy-visit\""
      refute_includes response.body, "meta name=\"ahoy-visitor\""
    end
  end

  test "bootstrap merges site tracking rules into frontend filters" do
    site = Analytics::Bootstrap.ensure_default_site!(host: "localhost")
    Analytics::TrackingRules.save!(
      include_paths: [ "/**" ],
      exclude_paths: [ "/preview/**" ],
      site: site
    )

    with_server_visits(true) do
      get root_path, headers: MODERN_BROWSER_HEADERS
    end

    assert_response :success
    assert_includes response.body, "\"includePaths\":[\"/**\"]"
    assert_includes response.body, "\"excludePaths\":[\"/admin\",\"/.well-known\",\"/analytics\",\"/a\",\"/ahoy\",\"/cable\",\"/preview/**\"]"
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

  test "analytics owns the public events endpoint without exposing ahoy engine routes" do
    route_paths = Rails.application.routes.routes.map { |route| route.path.spec.to_s }

    assert_includes route_paths, "/a/e(.:format)"
    refute_includes route_paths, "/ahoy"
    refute_includes route_paths, "/events(.:format)"
    refute_includes route_paths, "/visits(.:format)"
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
      assert_includes response.body, "\"tracking\":{\"hashBasedRouting\":false,\"initialPageviewTracked\":false"
      refute_includes response.body, "meta name=\"ahoy-visit\""
      refute_includes response.body, "meta name=\"ahoy-visitor\""
    end
  end

  private
    def with_server_visits(enabled)
      original = Analytics.config.server_visits
      Analytics.config.server_visits = enabled
      Analytics.install!
      yield
    ensure
      Analytics.config.server_visits = original
      Analytics.install!
    end
end
