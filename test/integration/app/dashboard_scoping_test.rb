# frozen_string_literal: true

require "test_helper"
require "json"

class App::DashboardScopingTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "dashboard props are scoped to the current account" do
    identity, account, = create_tenant(
      email: "dashboard-scope-#{SecureRandom.hex(4)}@example.com",
      name: "Dashboard User"
    )

    other_account = Account.create!(name: "Other Account", personal: false)
    other_account.users.create!(name: "System", role: :system)
    other_account.users.create!(identity: identity, name: "Dashboard User", role: :member)

    library = Library.create!(
      account: account,
      namespace: "account-a-#{SecureRandom.hex(4)}",
      name: "docs",
      display_name: "Account A Docs"
    )
    other_library = Library.create!(
      account: other_account,
      namespace: "account-b-#{SecureRandom.hex(4)}",
      name: "docs",
      display_name: "Account B Docs"
    )

    version = library.versions.create!(version: "1.0.0", channel: "stable")
    other_version = other_library.versions.create!(version: "2.0.0", channel: "stable")

    version.pages.create!(
      page_uid: "intro",
      path: "intro.md",
      title: "Intro",
      description: "Account A content"
    )
    other_version.pages.create!(
      page_uid: "intro",
      path: "intro.md",
      title: "Intro",
      description: "Account B content"
    )

    CrawlRequest.create!(
      identity: identity,
      library: library,
      url: "https://a.example/docs",
      source_type: "website",
      status: "pending"
    )
    CrawlRequest.create!(
      identity: identity,
      library: other_library,
      url: "https://b.example/docs",
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
    assert_equal [ "Account A Docs" ], page_props.dig("props", "recentLibraries").map { |lib| lib["displayName"] }
    assert_equal [ "Account A Docs" ], page_props.dig("props", "recentCrawls").map { |crawl| crawl["libraryName"] }
  ensure
    Current.reset
  end

  private
    def page_props
      page_node = Nokogiri::HTML5(response.body).at_css("script[data-page]")
      JSON.parse(page_node.text)
    end
end
