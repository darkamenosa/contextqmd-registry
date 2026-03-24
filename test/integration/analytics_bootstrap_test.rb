# frozen_string_literal: true

require "test_helper"

class AnalyticsBootstrapTest < ActionDispatch::IntegrationTest
  test "layout exposes analytics runtime config from rails settings" do
    get root_path

    assert_response :success
    assert_includes response.body, "\"visitDurationMinutes\":240"
    assert_includes response.body, "\"trackVisits\":true"
    assert_includes response.body, "\"useBeaconForEvents\":true"
    assert_includes response.body, "\"useCookies\":false"
  end
end
