# frozen_string_literal: true

require "test_helper"

class ProcessCrawlRequestJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

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

  teardown do
    FileUtils.rm_rf(DocsBundle.storage_root)
  end

  test "creates library, version, and pages from fetcher result" do
    ns = "example-#{SecureRandom.hex(4)}"
    lib_name = "my-lib-#{SecureRandom.hex(4)}"

    result = CrawlResult.new(
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

    with_stub_fetcher(result) do
      assert_difference -> { Library.count }, 1 do
        assert_difference -> { Version.count }, 1 do
          assert_difference -> { Page.count }, 2 do
            ProcessCrawlRequestJob.perform_now(@crawl_request)
          end
        end
      end
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

  test "enqueues a full bundle build after import instead of building inline" do
    result = CrawlResult.new(
      namespace: "bundle-ns-#{SecureRandom.hex(4)}",
      name: "bundle-lib-#{SecureRandom.hex(4)}",
      display_name: "Bundle Library",
      homepage_url: "https://example.com",
      aliases: [],
      version: "1.0.0",
      pages: [
        {
          page_uid: "readme",
          path: "README.md",
          title: "Readme",
          url: "https://example.com/readme",
          content: "# Readme\n\nBundle me.",
          headings: [ "Readme" ]
        }
      ]
    )

    with_stub_fetcher(result) do
      assert_enqueued_jobs 1, only: BuildBundleJob do
        ProcessCrawlRequestJob.perform_now(@crawl_request)
      end
    end

    version = @crawl_request.reload.library.versions.first
    bundle = version.bundles.find_by(profile: "full")

    assert_not_nil bundle
    assert_equal "pending", bundle.status
    assert_equal "public", bundle.visibility
    assert_equal "tar.gz", bundle.format
    assert_nil bundle.sha256
    assert_nil bundle.size_bytes
    assert_not File.exist?(bundle.file_path), "Bundle file should not exist until the build job runs"

    perform_enqueued_jobs only: BuildBundleJob

    bundle.reload
    assert_equal "ready", bundle.status
    assert_match(/\Asha256:[0-9a-f]{64}\z/, bundle.sha256)
    assert_operator bundle.size_bytes, :positive?
    assert bundle.package.attached?, "Expected bundle package to be attached after the build job runs"
    assert File.exist?(bundle.file_path), "Expected local bundle file to exist after the build job runs"
  end

  test "carries requested bundle visibility onto the scheduled bundle" do
    @crawl_request.update!(requested_bundle_visibility: "private")

    result = CrawlResult.new(
      namespace: "visibility-ns-#{SecureRandom.hex(4)}",
      name: "visibility-lib-#{SecureRandom.hex(4)}",
      display_name: "Visibility Library",
      homepage_url: "https://example.com",
      aliases: [],
      version: "1.0.0",
      pages: [
        {
          page_uid: "readme",
          path: "README.md",
          title: "Readme",
          url: "https://example.com/readme",
          content: "# Readme\n\nBundle me privately.",
          headings: [ "Readme" ]
        }
      ]
    )

    with_stub_fetcher(result) do
      ProcessCrawlRequestJob.perform_now(@crawl_request)
    end

    bundle = @crawl_request.reload.library.versions.first.bundles.find_by(profile: "full")
    assert_equal "private", bundle.visibility
  end

  test "sets default_version on library when blank" do
    result = CrawlResult.new(
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
    error_fetcher.define_singleton_method(:fetch) { |_crawl_request, **_opts| raise "Network error" }

    original_for = DocsFetcher.method(:for)
    DocsFetcher.define_singleton_method(:for) { |_source_type, **_opts| error_fetcher }

    # CrawlRequest#process marks itself failed, then re-raises
    assert_raises(RuntimeError) do
      ProcessCrawlRequestJob.perform_now(@crawl_request)
    end

    DocsFetcher.define_singleton_method(:for, original_for)

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

    result = CrawlResult.new(
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
    @crawl_request.define_singleton_method(:mark_processing) do
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

    system_account = Account.create!(name: "ContextQMD System", personal: false)
    existing = Library.create!(
      account: system_account,
      namespace: ns,
      name: lib_name,
      display_name: "Existing Lib"
    )

    result = CrawlResult.new(
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

  test "creates a non-personal system account instead of reusing a personal one with the same name" do
    Account.where(name: "ContextQMD System", personal: false).destroy_all
    Account.create!(name: "ContextQMD System", personal: true)

    result = CrawlResult.new(
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

    with_stub_fetcher(result) do
      assert_difference -> { Account.where(name: "ContextQMD System", personal: false).count }, 1 do
        ProcessCrawlRequestJob.perform_now(@crawl_request)
      end
    end

    library = @crawl_request.reload.library
    assert_not_nil library
    assert_equal false, library.account.personal
  end

  test "skips saving unchanged pages on re-crawl (deduplication)" do
    ns = "ns-#{SecureRandom.hex(4)}"
    lib_name = "lib-#{SecureRandom.hex(4)}"

    result = CrawlResult.new(
      namespace: ns, name: lib_name, display_name: "Lib",
      homepage_url: "https://example.com", aliases: [],
      version: nil,
      pages: [
        { page_uid: "intro", path: "intro.md", title: "Intro",
          url: "https://example.com", content: "Hello world", headings: [] }
      ]
    )

    # First crawl
    with_stub_fetcher(result) { ProcessCrawlRequestJob.perform_now(@crawl_request) }
    library = @crawl_request.reload.library
    version = library.versions.first
    page = version.pages.find_by(page_uid: "intro")
    original_updated_at = page.updated_at

    # Re-crawl with same content — page should NOT be re-saved
    cr2 = CrawlRequest.create!(identity: @identity, url: "https://example.com/llms.txt", source_type: "llms_txt", status: "pending")
    travel 1.minute do
      with_stub_fetcher(result) { ProcessCrawlRequestJob.perform_now(cr2) }
    end

    page.reload
    assert_equal original_updated_at, page.updated_at, "Unchanged page should not be re-saved"
  end

  test "removes stale pages on re-crawl" do
    ns = "ns-#{SecureRandom.hex(4)}"
    lib_name = "lib-#{SecureRandom.hex(4)}"

    result_v1 = CrawlResult.new(
      namespace: ns, name: lib_name, display_name: "Lib",
      homepage_url: "https://example.com", aliases: [],
      version: nil,
      pages: [
        { page_uid: "intro", path: "intro.md", title: "Intro",
          url: "https://example.com/intro", content: "Hello", headings: [] },
        { page_uid: "old-page", path: "old-page.md", title: "Old",
          url: "https://example.com/old", content: "Stale content", headings: [] }
      ]
    )

    with_stub_fetcher(result_v1) { ProcessCrawlRequestJob.perform_now(@crawl_request) }
    library = @crawl_request.reload.library
    version = library.versions.first
    assert_equal 2, version.pages.count

    # Re-crawl without old-page
    result_v2 = CrawlResult.new(
      namespace: ns, name: lib_name, display_name: "Lib",
      homepage_url: "https://example.com", aliases: [],
      version: nil,
      pages: [
        { page_uid: "intro", path: "intro.md", title: "Intro",
          url: "https://example.com/intro", content: "Hello updated", headings: [] }
      ]
    )

    cr2 = CrawlRequest.create!(identity: @identity, url: "https://example.com/llms.txt", source_type: "llms_txt", status: "pending")
    with_stub_fetcher(result_v2) { ProcessCrawlRequestJob.perform_now(cr2) }

    version.reload
    assert_equal 1, version.pages.count
    assert_nil version.pages.find_by(page_uid: "old-page"), "Stale page should be removed"
    assert_not_nil version.pages.find_by(page_uid: "intro")
  end

  test "promotes default_version when a newer concrete version is crawled" do
    ns = "ns-#{SecureRandom.hex(4)}"
    lib_name = "lib-#{SecureRandom.hex(4)}"

    result_v1 = CrawlResult.new(
      namespace: ns, name: lib_name, display_name: "Lib",
      homepage_url: "https://example.com", aliases: [],
      version: "1.0.0",
      pages: [
        { page_uid: "intro", path: "intro.md", title: "Intro",
          url: "https://example.com/intro", content: "Hello", headings: [] }
      ]
    )

    with_stub_fetcher(result_v1) { ProcessCrawlRequestJob.perform_now(@crawl_request) }

    library = @crawl_request.reload.library
    assert_equal "1.0.0", library.default_version

    result_v2 = CrawlResult.new(
      namespace: ns, name: lib_name, display_name: "Lib",
      homepage_url: "https://example.com", aliases: [],
      version: "1.1.0",
      pages: [
        { page_uid: "intro", path: "intro.md", title: "Intro",
          url: "https://example.com/intro", content: "Hello v1.1", headings: [] }
      ]
    )

    cr2 = CrawlRequest.create!(identity: @identity, url: "https://example.com/llms.txt", source_type: "llms_txt", status: "pending")

    with_stub_fetcher(result_v2) do
      assert_difference -> { library.versions.count }, 1 do
        ProcessCrawlRequestJob.perform_now(cr2)
      end
    end

    library.reload
    assert_equal "1.1.0", library.default_version
    assert library.versions.exists?(version: "1.0.0")
    assert library.versions.exists?(version: "1.1.0")
  end

  test "normalizes fetched library names into path-safe slugs" do
    result = CrawlResult.new(
      namespace: "reactjs",
      name: "react.dev",
      display_name: "React.dev",
      homepage_url: "https://github.com/reactjs/react.dev",
      aliases: [ "react.dev", "react-dev" ],
      version: "19.0.0",
      pages: [
        { page_uid: "intro", path: "README.md", title: "Intro",
          url: "https://github.com/reactjs/react.dev", content: "Hello", headings: [] }
      ]
    )

    with_stub_fetcher(result) do
      ProcessCrawlRequestJob.perform_now(@crawl_request)
    end

    @crawl_request.reload
    assert_equal "completed", @crawl_request.status
    assert_not_nil @crawl_request.library
    assert_equal "reactjs", @crawl_request.library.namespace
    assert_equal "react-dev", @crawl_request.library.name
    assert_includes @crawl_request.library.aliases, "react.dev"
  end

  test "normalizes fetched underscore library names into path-safe slugs" do
    result = CrawlResult.new(
      namespace: "ryanb",
      name: "letter_opener",
      display_name: "Letter Opener",
      homepage_url: "https://github.com/ryanb/letter_opener",
      aliases: [ "letter_opener", "letter-opener" ],
      version: "latest",
      pages: [
        { page_uid: "intro", path: "README.md", title: "Intro",
          url: "https://github.com/ryanb/letter_opener", content: "Hello", headings: [] }
      ]
    )

    with_stub_fetcher(result) do
      ProcessCrawlRequestJob.perform_now(@crawl_request)
    end

    @crawl_request.reload
    assert_equal "completed", @crawl_request.status
    assert_not_nil @crawl_request.library
    assert_equal "ryanb", @crawl_request.library.namespace
    assert_equal "letter-opener", @crawl_request.library.name
    assert_includes @crawl_request.library.aliases, "letter_opener"
  end

  test "adds punctuationless aliases for dotted library names" do
    result = CrawlResult.new(
      namespace: "vercel",
      name: "next-js",
      display_name: "Next.js",
      homepage_url: "https://github.com/vercel/next.js",
      aliases: [ "next.js", "next-js" ],
      version: "latest",
      pages: [
        { page_uid: "intro", path: "README.md", title: "Intro",
          url: "https://github.com/vercel/next.js", content: "Hello", headings: [] }
      ]
    )

    with_stub_fetcher(result) do
      ProcessCrawlRequestJob.perform_now(@crawl_request)
    end

    @crawl_request.reload
    assert_equal "completed", @crawl_request.status
    assert_not_nil @crawl_request.library
    assert_includes @crawl_request.library.aliases, "next.js"
    assert_includes @crawl_request.library.aliases, "next-js"
    assert_includes @crawl_request.library.aliases, "nextjs"
  end

  private

    def stub_docs_fetcher(result)
      fetcher = Object.new
      fetcher.define_singleton_method(:fetch) { |_crawl_request, **_opts| result }
      fetcher
    end

    def with_stub_fetcher(result)
      stub = stub_docs_fetcher(result)
      original_for = DocsFetcher.method(:for)
      DocsFetcher.define_singleton_method(:for) { |_source_type, **_opts| stub }
      yield
    ensure
      DocsFetcher.define_singleton_method(:for, original_for)
    end
end
