# frozen_string_literal: true

require "test_helper"
require "json"

class App::DashboardScopingTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "dashboard props show the user's crawl requests and resulting libraries" do
    identity, account, user = create_tenant(
      email: "dashboard-scope-#{SecureRandom.hex(4)}@example.com",
      name: "Dashboard User"
    )

    other_identity = Identity.create!(
      email: "other-#{SecureRandom.hex(4)}@example.com",
      password: "password123456"
    )
    other_account = Account.create!(name: "Other Account", personal: true)
    other_user = other_account.users.create!(identity: other_identity, name: "Other User", role: :owner)

    system_account = Account.system

    hex = SecureRandom.hex(4)
    library = Library.create!(
      account: system_account,
      namespace: "my-lib-#{hex}",
      name: "docs-#{hex}",
      slug: "my-lib-docs-#{hex}",
      display_name: "My Lib Docs"
    )
    other_library = Library.create!(
      account: system_account,
      namespace: "other-lib-#{hex}",
      name: "other-#{hex}",
      slug: "other-lib-docs-#{hex}",
      display_name: "Other Lib Docs"
    )

    version = library.versions.create!(version: "1.0.0", channel: "stable")
    other_version = other_library.versions.create!(version: "2.0.0", channel: "stable")

    version.pages.create!(
      page_uid: "intro",
      path: "intro.md",
      title: "Intro",
      description: "My content"
    )
    other_version.pages.create!(
      page_uid: "intro",
      path: "intro.md",
      title: "Intro",
      description: "Other content"
    )

    CrawlRequest.create!(
      creator: user,
      library: library,
      url: "https://example.com/docs-a",
      source_type: "website",
      status: "pending"
    )
    CrawlRequest.create!(
      creator: other_user,
      library: other_library,
      url: "https://example.com/docs-b",
      source_type: "website",
      status: "pending"
    )

    sign_in(identity)

    get app_dashboard_path(account_id: account.external_account_id)

    assert_response :success
    assert_equal 1, page_props.dig("props", "stats", "libraryCount")
    assert_equal 1, page_props.dig("props", "stats", "versionCount")
    assert_equal 1, page_props.dig("props", "stats", "pageCount")
    assert_equal 1, page_props.dig("props", "stats", "crawlPending")
    assert_equal [ "My Lib Docs" ], page_props.dig("props", "recentLibraries").map { |lib| lib["displayName"] }
    assert_equal [ "My Lib Docs" ], page_props.dig("props", "recentCrawls").map { |crawl| crawl["libraryName"] }
  ensure
    Current.reset
  end

  private
    def page_props
      page_node = Nokogiri::HTML5(response.body).at_css("script[data-page]")
      JSON.parse(page_node.text)
    end
end
