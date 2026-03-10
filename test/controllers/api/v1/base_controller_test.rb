# frozen_string_literal: true

require "test_helper"

# Test controllers that inherit from BaseController to exercise auth behavior.
module Api
  module V1
    # Default: inherits authenticate_api_token! (auth required)
    class TestPingController < BaseController
      def show
        render_data({ pong: true })
      end
    end

    # Public: skips auth (like libraries, resolve, etc.)
    class TestPublicController < BaseController
      skip_before_action :authenticate_api_token!

      def show
        render_data({ public: true })
      end
    end
  end
end

module Api
  module V1
    class BaseControllerTest < ActionDispatch::IntegrationTest
      PING_PATH = "/api/v1/test-ping"
      PUBLIC_PATH = "/api/v1/test-public"

      setup do
        Rails.application.routes.draw do
          namespace :api do
            namespace :v1 do
              get "test-ping", to: "test_ping#show"
              get "test-public", to: "test_public#show"
            end
          end
        end
      end

      teardown do
        Rails.application.reload_routes!
      end

      # -- Default behavior: auth required --

      test "unauthenticated request returns 401 by default" do
        get PING_PATH

        assert_response :unauthorized
      end

      test "invalid token returns 401" do
        get PING_PATH, headers: {
          "Authorization" => "Token invalid-token"
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
          "Authorization" => "Token #{raw_token}"
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
          "Authorization" => "Token #{raw_token}"
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
          "Authorization" => "Token #{raw_token}"
        }

        assert_response :unauthorized
      ensure
        Current.reset
      end

      # -- Public endpoints: skip_before_action :authenticate_api_token! --

      test "public endpoint works without auth" do
        get PUBLIC_PATH

        assert_response :ok
        body = response.parsed_body
        assert_equal true, body["data"]["public"]
      end

      test "public endpoint works with valid token" do
        identity, = create_tenant(
          email: "api-pub-#{SecureRandom.hex(4)}@example.com",
          name: "API Public"
        )
        _access_token, raw_token = AccessToken.generate(
          identity: identity,
          name: "Pub Token",
          permission: :read
        )

        get PUBLIC_PATH, headers: {
          "Authorization" => "Token #{raw_token}"
        }

        assert_response :ok
        body = response.parsed_body
        assert_equal true, body["data"]["public"]
      ensure
        Current.reset
      end
    end
  end
end
