# frozen_string_literal: true

require "test_helper"

class Admin::RoutingErrorsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "unauthenticated users visiting mission control jobs are redirected to the global login" do
    get "/admin/jobs"

    assert_redirected_to "/login"
  ensure
    Current.reset
  end

  test "unauthenticated users visiting unknown admin paths are redirected to login" do
    get "/admin/analytics"

    assert_redirected_to new_identity_session_path
  ensure
    Current.reset
  end

  test "staff users visiting unknown admin paths get the admin not found page" do
    staff_identity, = create_tenant(
      email: "staff-admin-404-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Admin 404"
    )
    staff_identity.update!(staff: true)

    sign_in(staff_identity)

    get "/admin/analytics"

    assert_response :not_found
    assert_equal "admin/errors/show", page_payload.fetch("component")
    assert_equal 404, page_payload.dig("props", "status")
  ensure
    Current.reset
  end

  test "staff users can access mission control jobs without a redirect loop" do
    staff_identity, = create_tenant(
      email: "staff-admin-jobs-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Admin Jobs"
    )
    staff_identity.update!(staff: true)

    sign_in(staff_identity)

    get "/admin/jobs", headers: { "User-Agent" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" }

    assert_response :success
  ensure
    Current.reset
  end

  private

    def page_payload
      page_node = Nokogiri::HTML5(response.body).at_css("script[data-page]")
      JSON.parse(page_node.text)
    end
end
