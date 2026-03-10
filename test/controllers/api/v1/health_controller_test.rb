# frozen_string_literal: true

require "test_helper"

module Api
  module V1
    class HealthControllerTest < ActionDispatch::IntegrationTest
      test "returns ok status without auth" do
        get api_v1_health_path

        assert_response :ok
        body = response.parsed_body
        assert_equal "ok", body["data"]["status"]
        assert_equal "1.0.0", body["data"]["version"]
      end

      test "response has correct envelope" do
        get api_v1_health_path

        body = response.parsed_body
        assert body.key?("data"), "Should have data key"
        assert body.key?("meta"), "Should have meta key"
      end
    end
  end
end
