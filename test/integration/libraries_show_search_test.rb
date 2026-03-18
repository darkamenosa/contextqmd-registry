# frozen_string_literal: true

require "test_helper"
require "json"

class LibrariesShowSearchTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  fixtures :accounts, :libraries, :versions, :pages, :source_policies

  setup do
    @original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    clear_performed_jobs
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
    ActiveJob::Base.queue_adapter = @original_queue_adapter
  end

  test "two-character search stays active and uses count-less pagination" do
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
    assert_equal true, page_props.dig("props", "searchActive")
    assert_equal false, page_props.dig("props", "pagination", "countKnown")
    assert_nil page_props.dig("props", "pagination", "total")
    assert_nil page_props.dig("props", "pagination", "pages")
    assert_equal 1, page_props.dig("props", "pages").size
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

  test "show enqueues a source check when the primary source is overdue" do
    library = libraries(:nextjs)
    library.library_sources.create!(
      url: "https://nextjs.org/docs",
      source_type: "website",
      primary: true,
      next_version_check_at: 1.hour.ago
    )

    assert_enqueued_jobs 1, only: CheckLibrarySourceJob do
      get "/libraries/nextjs"
    end

    assert_response :success
  end

  private

    def page_props
      page_node = Nokogiri::HTML5(response.body).at_css("script[data-page]")
      JSON.parse(page_node.text)
    end
end
