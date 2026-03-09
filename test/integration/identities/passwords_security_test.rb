# frozen_string_literal: true

require "test_helper"
require "json"

class Identities::PasswordsSecurityTest < ActionDispatch::IntegrationTest
  test "password reset validation failures do not leak the raw token in the redirect url" do
    identity = Identity.create!(
      email: "password-security-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )
    raw_token = identity.send(:set_reset_password_token)

    put identity_password_path, params: {
      identity: {
        password: "new-password-123",
        password_confirmation: "different-password-123",
        reset_password_token: raw_token
      }
    }

    assert_redirected_to edit_identity_password_path
    assert_not_includes response.location, raw_token

    follow_redirect!

    assert_response :success
    assert_equal raw_token, page_props.dig("props", "resetPasswordToken")
  ensure
    Current.reset
  end

  private
    def page_props
      page_node = Nokogiri::HTML5(response.body).at_css("script[data-page]")
      JSON.parse(page_node.text)
    end
end
