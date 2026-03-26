# frozen_string_literal: true

require "test_helper"
require "json"

class Admin::DashboardRecentCrawlsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "dashboard labels system-created crawl requests as System" do
    staff_identity, = create_tenant(
      email: "staff-dashboard-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Admin"
    )
    staff_identity.update!(staff: true)

    crawl_request = CrawlRequest.create!(
      url: "https://github.com/example/docs",
      source_type: "github",
      status: "completed"
    )

    sign_in(staff_identity)

    get admin_dashboard_path

    assert_response :success
    crawl_props = page_props.fetch("props").fetch("recentCrawls").find do |item|
      item["id"] == crawl_request.id
    end
    assert_equal "System", crawl_props["submittedBy"]
  ensure
    Current.reset
  end

  private

    def page_props
      page_node = Nokogiri::HTML5(response.body).at_css("script[data-page]")
      JSON.parse(page_node.text)
    end
end
