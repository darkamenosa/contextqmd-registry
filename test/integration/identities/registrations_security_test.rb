# frozen_string_literal: true

require "test_helper"
require "json"

class Identities::RegistrationsSecurityTest < ActionDispatch::IntegrationTest
  test "duplicate email registration returns a generic error" do
    identity, = create_tenant(
      email: "registration-security-#{SecureRandom.hex(4)}@example.com",
      name: "Existing Registration"
    )

    post identity_registration_path, params: {
      identity: {
        email: identity.email,
        password: "password123"
      },
      user: {
        name: "Duplicate Registration"
      }
    }

    assert_redirected_to new_identity_registration_path

    follow_redirect!

    assert_response :success
    assert_equal(
      "We couldn't create your account. Try signing in or resetting your password.",
      page_props.dig("props", "errors", "email")
    )
  end

  private
    def page_props
      page_node = Nokogiri::HTML5(response.body).at_css("script[data-page]")
      JSON.parse(page_node.text)
    end
end
