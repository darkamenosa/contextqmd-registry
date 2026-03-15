# frozen_string_literal: true

require "test_helper"
require "json"

class HomepageLibraryLinksTest < ActionDispatch::IntegrationTest
  test "home page exposes canonical library slug for links" do
    account = Account.create!(name: "Homepage Test Account", personal: true)
    account.users.create!(name: "System", role: :system)

    library = Library.create!(
      account: account,
      namespace: "laravel",
      name: "docs",
      slug: "laravel",
      display_name: "Laravel"
    )
    version = library.versions.create!(version: "12.x", channel: "stable")
    version.pages.create!(
      page_uid: "intro",
      path: "intro.md",
      title: "Introduction",
      description: "Laravel intro"
    )

    get root_path

    assert_response :success
    library_props = page_props.fetch("props").fetch("libraries").find { |item| item["displayName"] == "Laravel" }
    assert_equal "laravel", library_props["slug"]
  end

  private

    def page_props
      page_node = Nokogiri::HTML5(response.body).at_css("script[data-page]")
      JSON.parse(page_node.text)
    end
end
