# frozen_string_literal: true

require "test_helper"
require "json"

class Admin::LibrariesIndexTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "index exposes canonical slug in library rows" do
    staff_identity, = create_tenant(
      email: "staff-library-index-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Admin"
    )
    staff_identity.update!(staff: true)

    _owner_identity, account, = create_tenant(
      email: "library-index-owner-#{SecureRandom.hex(4)}@example.com",
      name: "Library Owner"
    )
    library = Library.create!(
      account: account,
      namespace: "basecamp",
      name: "kamal-site",
      slug: "kamal",
      display_name: "Kamal",
      homepage_url: "https://github.com/basecamp/kamal-site"
    )

    sign_in(staff_identity)

    get admin_libraries_path

    assert_response :success
    row = page_props.fetch("props").fetch("libraries").find { |item| item["id"] == library.id }
    assert_equal "kamal", row["slug"]
  ensure
    Current.reset
  end

  private

    def page_props
      page_node = Nokogiri::HTML5(response.body).at_css("script[data-page]")
      JSON.parse(page_node.text)
    end
end
