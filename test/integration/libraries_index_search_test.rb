# frozen_string_literal: true

require "test_helper"
require "json"

class LibrariesIndexSearchTest < ActionDispatch::IntegrationTest
  fixtures :accounts, :libraries, :versions, :pages, :source_policies

  test "query search includes full-text matches even when an exact alias exists" do
    Library.create!(
      account: accounts(:personal),
      namespace: "rails",
      name: "exact",
      slug: "rails-exact",
      display_name: "Rails Exact",
      aliases: [ "rails" ]
    )

    Library.create!(
      account: accounts(:personal),
      namespace: "inertia",
      name: "rails-adapter",
      slug: "a-rails-adapter",
      display_name: "Inertia Rails",
      aliases: [ "inertia-rails" ]
    )

    get "/libraries", params: { query: "rails" }

    assert_response :success

    slugs = page_props.dig("props", "libraries").map { |library| library.fetch("slug") }

    assert_equal "rails", slugs.first
    assert_includes slugs, "rails-exact"
    assert_includes slugs, "a-rails-adapter"
  end

  private

    def page_props
      page_node = Nokogiri::HTML5(response.body).at_css("script[data-page]")
      JSON.parse(page_node.text)
    end
end
