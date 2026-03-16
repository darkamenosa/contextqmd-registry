# frozen_string_literal: true

require "test_helper"
require "json"

class LibrariesShowSearchTest < ActionDispatch::IntegrationTest
  fixtures :accounts, :libraries, :versions, :pages, :source_policies

  test "short search query keeps normal pagination and exposes the minimum length" do
    version = versions(:nextjs_stable)
    pages(:installation).update!(description: "Deploy your app")
    pages(:routing).update!(description: "Route incoming requests")
    version.pages.create!(
      page_uid: "pg_misc_001",
      path: "reference/misc.md",
      title: "Misc",
      description: "Completely unrelated",
      url: "https://nextjs.org/docs/reference/misc",
      bytes: 128
    )

    get "/libraries/nextjs", params: { version: version.version, search: "de" }

    assert_response :success
    assert_equal false, page_props.dig("props", "searchActive")
    assert_equal 3, page_props.dig("props", "minimumSearchLength")
    assert_equal true, page_props.dig("props", "pagination", "countKnown")
    assert_equal 3, page_props.dig("props", "pages").size
  end

  test "active search uses count-less pagination" do
    version = versions(:nextjs_stable)

    31.times do |i|
      version.pages.create!(
        page_uid: "pg_search_#{i}",
        path: "guides/deploy-#{i}.md",
        title: "Deploy #{i}",
        description: "How to deploy application #{i}",
        url: "https://nextjs.org/docs/guides/deploy-#{i}",
        bytes: 512
      )
    end

    get "/libraries/nextjs", params: { version: version.version, search: "deploy" }

    assert_response :success
    assert_equal true, page_props.dig("props", "searchActive")
    assert_equal false, page_props.dig("props", "pagination", "countKnown")
    assert_nil page_props.dig("props", "pagination", "total")
    assert_nil page_props.dig("props", "pagination", "pages")
    assert_equal 30, page_props.dig("props", "pages").size
    assert_equal true, page_props.dig("props", "pagination", "hasNext")
  end

  private

    def page_props
      page_node = Nokogiri::HTML5(response.body).at_css("script[data-page]")
      JSON.parse(page_node.text)
    end
end
