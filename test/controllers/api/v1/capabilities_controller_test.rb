# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class CapabilitiesControllerTest < ActionDispatch::IntegrationTest
      test "returns capabilities without auth" do
        get api_v1_capabilities_path

        assert_response :ok
        body = response.parsed_body
        assert_equal "ContextQMD Registry", body["data"]["name"]
        assert_equal "1.0", body["data"]["version"]
      end

      test "includes all feature flags" do
        get api_v1_capabilities_path

        features = response.parsed_body["data"]["features"]
        assert_equal true, features["bundle_download"]
        assert_equal true, features["cursor_pagination"]
        assert_equal true, features["origin_fetch_recipes"]
        assert_equal false, features["signed_manifests"]
        assert_equal false, features["delta_sync"]
      end

      test "response has correct envelope" do
        get api_v1_capabilities_path

        body = response.parsed_body
        assert body.key?("data"), "Should have data key"
        assert body.key?("meta"), "Should have meta key"
      end
    end
  end
end
