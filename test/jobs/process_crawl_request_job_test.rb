# frozen_string_literal: true

require "test_helper"

class ProcessCrawlRequestJobTest < ActiveSupport::TestCase
  setup do
    identity, @account, _user = create_tenant
    @identity = identity

    @crawl_request = CrawlRequest.create!(
      identity: @identity,
      url: "https://example.com/llms.txt",
      source_type: "llms_txt",
      status: "pending"
    )
  end

  test "creates library, version, and pages from fetcher result" do
    ns = "example-#{SecureRandom.hex(4)}"
    lib_name = "my-lib-#{SecureRandom.hex(4)}"

    result = DocsFetcher::Result.new(
      namespace: ns,
      name: lib_name,
      display_name: "My Library",
      homepage_url: "https://example.com",
      aliases: [ "my-lib" ],
      version: nil,
      pages: [
        {
          page_uid: "getting-started",
          path: "getting-started.md",
          title: "Getting Started",
          url: "https://example.com/llms.txt#getting-started",
          content: "Install with npm install my-lib",
          headings: [ "Prerequisites", "Steps" ]
        },
        {
          page_uid: "api-reference",
          path: "api-reference.md",
          title: "API Reference",
          url: "https://example.com/llms.txt#api-reference",
          content: "## Functions\n\n### create()\n\nCreates a thing.",
          headings: [ "Functions" ]
        }
      ]
    )

    stub_fetcher = stub_docs_fetcher(result)

    original_for = DocsFetcher.method(:for)
    DocsFetcher.define_singleton_method(:for) { |_source_type| stub_fetcher }

    begin
      assert_difference -> { Library.count }, 1 do
        assert_difference -> { Version.count }, 1 do
          assert_difference -> { Page.count }, 2 do
            ProcessCrawlRequestJob.perform_now(@crawl_request)
          end
        end
      end
    ensure
      DocsFetcher.define_singleton_method(:for, original_for)
    end

    @crawl_request.reload
    assert_equal "completed", @crawl_request.status
    assert_not_nil @crawl_request.library

    library = @crawl_request.library
    assert_equal ns, library.namespace
    assert_equal lib_name, library.name
    assert_equal "My Library", library.display_name
    assert_equal "https://example.com", library.homepage_url

    version = library.versions.first
    assert_equal "latest", version.version
    assert_equal "latest", version.channel
    assert_equal 2, version.pages.count

    page = version.pages.find_by(page_uid: "getting-started")
    assert_equal "Getting Started", page.title
    assert_equal "Install with npm install my-lib", page.description
    assert_equal [ "Prerequisites", "Steps" ], page.headings
  end

  test "sets default_version on library when blank" do
    result = DocsFetcher::Result.new(
      namespace: "ns-#{SecureRandom.hex(4)}",
      name: "lib-#{SecureRandom.hex(4)}",
      display_name: "Lib",
      homepage_url: "https://example.com",
      aliases: [],
      version: "2.0.0",
      pages: [
        { page_uid: "index", path: "index.md", title: "Index",
          url: "https://example.com", content: "Hello", headings: [] }
      ]
    )

    with_stub_fetcher(result) do
      ProcessCrawlRequestJob.perform_now(@crawl_request)
    end

    library = @crawl_request.reload.library
    assert_equal "2.0.0", library.default_version

    version = library.versions.first
    assert_equal "2.0.0", version.version
    assert_equal "stable", version.channel
  end

  test "marks crawl request as failed on error" do
    error_fetcher = Object.new
    error_fetcher.define_singleton_method(:fetch) { |_url| raise "Network error" }

    original_for = DocsFetcher.method(:for)
    DocsFetcher.define_singleton_method(:for) { |_source_type| error_fetcher }

    # retry_on with perform_now retries inline; after all attempts the job
    # may or may not re-raise depending on Rails version.  We handle both.
    begin
      ProcessCrawlRequestJob.perform_now(@crawl_request)
    rescue RuntimeError
      # expected — some Rails versions re-raise after final retry
    ensure
      DocsFetcher.define_singleton_method(:for, original_for)
    end

    @crawl_request.reload
    assert_equal "failed", @crawl_request.status
    assert_includes @crawl_request.error_message, "Network error"
  end

  test "skips processing when crawl request is not pending" do
    @crawl_request.update!(status: "completed")

    assert_no_difference -> { Library.count } do
      ProcessCrawlRequestJob.perform_now(@crawl_request)
    end
  end

  test "transitions status to processing then completed" do
    statuses = []

    result = DocsFetcher::Result.new(
      namespace: "ns-#{SecureRandom.hex(4)}",
      name: "lib-#{SecureRandom.hex(4)}",
      display_name: "Lib",
      homepage_url: "https://example.com",
      aliases: [],
      version: nil,
      pages: [
        { page_uid: "index", path: "index.md", title: "Index",
          url: "https://example.com", content: "Content", headings: [] }
      ]
    )

    # Track status transitions
    @crawl_request.define_singleton_method(:start_processing!) do
      statuses << "processing"
      super()
    end

    with_stub_fetcher(result) do
      ProcessCrawlRequestJob.perform_now(@crawl_request)
    end

    assert_includes statuses, "processing"
    assert_equal "completed", @crawl_request.reload.status
  end

  test "reuses existing library when namespace and name match" do
    ns = "ns-#{SecureRandom.hex(4)}"
    lib_name = "lib-#{SecureRandom.hex(4)}"

    system_account = Account.find_or_create_by!(name: "ContextQMD System") { |a| a.personal = false }
    existing = Library.create!(
      account: system_account,
      namespace: ns,
      name: lib_name,
      display_name: "Existing Lib"
    )

    result = DocsFetcher::Result.new(
      namespace: ns,
      name: lib_name,
      display_name: "Updated Lib",
      homepage_url: "https://example.com",
      aliases: [],
      version: nil,
      pages: [
        { page_uid: "index", path: "index.md", title: "Index",
          url: "https://example.com", content: "Content", headings: [] }
      ]
    )

    with_stub_fetcher(result) do
      assert_no_difference -> { Library.count } do
        ProcessCrawlRequestJob.perform_now(@crawl_request)
      end
    end

    @crawl_request.reload
    assert_equal existing.id, @crawl_request.library_id
  end

  private

    def stub_docs_fetcher(result)
      fetcher = Object.new
      fetcher.define_singleton_method(:fetch) { |_url| result }
      fetcher
    end

    def with_stub_fetcher(result)
      stub = stub_docs_fetcher(result)
      original_for = DocsFetcher.method(:for)
      DocsFetcher.define_singleton_method(:for) { |_source_type| stub }
      yield
    ensure
      DocsFetcher.define_singleton_method(:for, original_for)
    end
end
