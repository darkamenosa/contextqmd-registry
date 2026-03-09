# frozen_string_literal: true

require "test_helper"

# Minimal test controller that inherits from BaseController so we can
# exercise token authentication without depending on real endpoint
# controllers that may not exist yet.
module Api
  module V1
    class TestPingController < BaseController
      def show
        render_data({ pong: true })
      end
    end
  end
end

module Api
  module V1
    class BaseControllerTest < ActionDispatch::IntegrationTest
      PING_PATH = "/api/v1/test-ping"

      setup do
        Rails.application.routes.draw do
          namespace :api do
            namespace :v1 do
              match "test-ping", to: "test_ping#show", via: [ :get, :post ]
            end
          end
        end
      end

      teardown do
        Rails.application.reload_routes!
      end

      test "unauthenticated request returns 401" do
        get PING_PATH

        assert_response :unauthorized
      end

      test "invalid token returns 401" do
        get PING_PATH, headers: {
          "Authorization" => "Bearer invalid-token"
        }

        assert_response :unauthorized
      end

      test "valid token returns 200 with envelope" do
        identity, = create_tenant(
          email: "api-valid-#{SecureRandom.hex(4)}@example.com",
          name: "API Valid"
        )
        _access_token, raw_token = AccessToken.generate(
          identity: identity,
          name: "Valid Token",
          permission: :read
        )

        get PING_PATH, headers: {
          "Authorization" => "Bearer #{raw_token}"
        }

        assert_response :ok
        body = response.parsed_body
        assert body.key?("data"), "Response should wrap payload in 'data' key"
        assert body.key?("meta"), "Response should include 'meta' key"
        assert_equal true, body["data"]["pong"]
      ensure
        Current.reset
      end

      test "expired token returns 401" do
        identity, = create_tenant(
          email: "api-expired-#{SecureRandom.hex(4)}@example.com",
          name: "API Expired"
        )
        _access_token, raw_token = AccessToken.generate(
          identity: identity,
          name: "Expired Token",
          permission: :read,
          expires_at: 1.day.ago
        )

        get PING_PATH, headers: {
          "Authorization" => "Bearer #{raw_token}"
        }

        assert_response :unauthorized
      ensure
        Current.reset
      end

      test "suspended identity returns 401" do
        identity, = create_tenant(
          email: "api-suspended-#{SecureRandom.hex(4)}@example.com",
          name: "API Suspended"
        )
        _access_token, raw_token = AccessToken.generate(
          identity: identity,
          name: "Suspended Token",
          permission: :read
        )
        identity.suspend

        get PING_PATH, headers: {
          "Authorization" => "Bearer #{raw_token}"
        }

        assert_response :unauthorized
      ensure
        Current.reset
      end

      test "read token cannot perform write requests" do
        identity, = create_tenant(
          email: "api-readonly-#{SecureRandom.hex(4)}@example.com",
          name: "API ReadOnly"
        )
        _access_token, raw_token = AccessToken.generate(
          identity: identity,
          name: "Read Token",
          permission: :read
        )

        # POST requires write permission; read tokens should be rejected
        post PING_PATH, headers: {
          "Authorization" => "Bearer #{raw_token}"
        }

        assert_response :unauthorized
      ensure
        Current.reset
      end
    end
  end
end
