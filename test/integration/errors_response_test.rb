# frozen_string_literal: true

require "test_helper"

class ErrorsResponseTest < ActionDispatch::IntegrationTest
  test "error page route returns json for json requests" do
    get error_path(status: 403), as: :json

    assert_response :forbidden
    assert_equal(
      { "error" => "You don't have permission to access this page.", "status" => 403 },
      response.parsed_body
    )
  end
end
