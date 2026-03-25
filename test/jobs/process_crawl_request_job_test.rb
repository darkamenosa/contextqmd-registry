# frozen_string_literal: true

require "test_helper"

class ProcessCrawlRequestJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    _identity, @account, @user = create_tenant

    @crawl_request = CrawlRequest.create!(
      creator: @user,
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

  test "deconflicts colliding page_uids during import" do
    crawl_request = CrawlRequest.create!(
      creator: @user,
      url: "https://github.com/example/docs-repo",
      source_type: "github",
      status: "pending"
    )

    result = CrawlResult.new(
      slug: "example",
      namespace: "example",
      name: "docs-repo",
      display_name: "Example",
      homepage_url: "https://github.com/example/docs-repo",
      aliases: [ "example", "example/docs-repo" ],
      version: "latest",
      pages: [
        {
          page_uid: "intro",
          path: "intro.md",
          title: "Intro",
          url: "https://github.com/example/docs-repo/blob/main/intro.md",
          content: "First page",
          headings: []
        },
        {
          page_uid: "intro",
          path: "duplicate.md",
          title: "Duplicate",
          url: "https://github.com/example/docs-repo/blob/main/duplicate.md",
          content: "Duplicate uid",
          headings: []
        }
      ]
    )

    with_stub_fetcher(result) do
      assert_difference -> { Page.count }, 2 do
        ProcessCrawlRequestJob.perform_now(crawl_request)
      end
    end

    crawl_request.reload
    assert_equal "completed", crawl_request.status

    version = crawl_request.library.versions.find_by!(version: "latest")
    pages = version.pages.order(:page_uid).to_a

    assert_equal 2, pages.size
    assert_equal pages.map(&:page_uid).uniq, pages.map(&:page_uid)
    assert_includes pages.map(&:page_uid), "intro"
    assert_equal 1, pages.count { |page| page.page_uid.match?(/\Aintro-/) }
    assert_equal [ "intro.md", "duplicate.md" ], pages.map(&:path)
  end

  test "skips oversized pages and imports the remaining content" do
    crawl_request = CrawlRequest.create!(
      creator: @user,
      url: "https://github.com/example/docs-repo",
      source_type: "github",
      status: "pending"
    )

    result = CrawlResult.new(
      slug: "example-docs",
      namespace: "example",
      name: "docs-repo",
      display_name: "Example Docs",
      homepage_url: "https://github.com/example/docs-repo",
      aliases: [ "example/docs-repo" ],
      version: "latest",
      pages: [
        {
          page_uid: "intro",
          path: "intro.md",
          title: "Intro",
          url: "https://github.com/example/docs-repo/blob/main/intro.md",
          content: "Intro content",
          headings: []
        },
        {
          page_uid: "huge-reference",
          path: "docs/reference.md",
          title: "Reference",
          url: "https://github.com/example/docs-repo/blob/main/docs/reference.md",
          content: "x" * (Page::MAX_DESCRIPTION_LENGTH + 1),
          headings: []
        }
      ]
    )

    with_stub_fetcher(result) do
      assert_difference -> { Page.count }, 1 do
        ProcessCrawlRequestJob.perform_now(crawl_request)
      end
    end

    crawl_request.reload
    assert_equal "completed", crawl_request.status
    assert_equal 1, crawl_request.library.versions.first.pages.count
    assert_nil crawl_request.library.versions.first.pages.find_by(page_uid: "huge-reference")
  end

  test "fails when every fetched page exceeds the max page size" do
    crawl_request = CrawlRequest.create!(
      creator: @user,
      url: "https://github.com/example/huge-docs",
      source_type: "github",
      status: "pending"
    )

    result = CrawlResult.new(
      slug: "huge-docs",
      namespace: "example",
      name: "huge-docs",
      display_name: "Huge Docs",
      homepage_url: "https://github.com/example/huge-docs",
      aliases: [ "example/huge-docs" ],
      version: "latest",
      pages: [
        {
          page_uid: "huge",
          path: "huge.md",
          title: "Huge",
          url: "https://github.com/example/huge-docs/blob/main/huge.md",
          content: "x" * (Page::MAX_DESCRIPTION_LENGTH + 1),
          headings: []
        }
      ]
    )

    with_stub_fetcher(result) do
      assert_raises(DocsFetcher::PermanentFetchError) do
        ProcessCrawlRequestJob.perform_now(crawl_request)
      end
    end

    crawl_request.reload
    assert_equal "failed", crawl_request.status
    assert_equal "No importable pages remained for https://github.com/example/huge-docs", crawl_request.error_message
  end

  test "skips processing when crawl request is not pending" do
    @crawl_request.update!(status: "completed")

    assert_no_difference -> { Library.count } do
      ProcessCrawlRequestJob.perform_now(@crawl_request)
    end
  end

  test "creates website crawl domain and enqueues website crawl job for website source types" do
    website_request = CrawlRequest.create!(
      creator: @user,
      url: "https://example.com/docs",
      source_type: "website",
      status: "pending"
    )

    clear_enqueued_jobs

    assert_difference -> { WebsiteCrawl.count }, 1 do
      assert_enqueued_with(job: ProcessWebsiteCrawlJob) do
        ProcessCrawlRequestJob.perform_now(website_request)
      end
    end

    website_crawl = WebsiteCrawl.find_by!(crawl_request: website_request)
    assert_equal "pending", website_crawl.status
  end

  test "does not enqueue duplicate website crawl jobs when website crawl already exists" do
    website_request = CrawlRequest.create!(
      creator: @user,
      url: "https://example.com/docs",
      source_type: "website",
      status: "pending"
    )
    WebsiteCrawl.create!(crawl_request: website_request)
    clear_enqueued_jobs

    assert_no_difference -> { WebsiteCrawl.count } do
      assert_no_enqueued_jobs only: ProcessWebsiteCrawlJob do
        ProcessCrawlRequestJob.perform_now(website_request)
      end
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

    with_stub_fetcher(result) do
      ProcessCrawlRequestJob.perform_now(@crawl_request)
    end

    @crawl_request.reload
    assert_equal "completed", @crawl_request.status
    assert_not_nil @crawl_request.started_at
  end

  test "reuses existing library when namespace and name match" do
    ns = "ns-#{SecureRandom.hex(4)}"
    lib_name = "lib-#{SecureRandom.hex(4)}"

    system_account = Account.system
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

  test "does not merge unrelated github libraries during import" do
    laravel_result = CrawlResult.new(
      slug: "laravel",
      namespace: "laravel",
      name: "docs",
      display_name: "Laravel",
      homepage_url: "https://github.com/laravel/docs",
      aliases: [ "laravel", "docs", "laravel/docs", "github.com" ],
      version: "12.x",
      pages: [
        { page_uid: "intro", path: "intro.md", title: "Intro",
          url: "https://github.com/laravel/docs/blob/12.x/intro.md", content: "Laravel", headings: [] }
      ]
    )

    with_stub_fetcher(laravel_result) do
      ProcessCrawlRequestJob.perform_now(@crawl_request)
    end

    first_library = @crawl_request.reload.library
    assert_equal "laravel", first_library.slug

    second_request = CrawlRequest.create!(
      creator: @user,
      url: "https://github.com/basecamp/kamal-site",
      source_type: "github",
      status: "pending"
    )
    kamal_result = CrawlResult.new(
      slug: "kamal-site",
      namespace: "basecamp",
      name: "kamal-site",
      display_name: "Kamal Site",
      homepage_url: "https://github.com/basecamp/kamal-site",
      aliases: [ "kamal-site", "basecamp/kamal-site" ],
      version: "latest",
      pages: [
        { page_uid: "intro", path: "intro.md", title: "Intro",
          url: "https://github.com/basecamp/kamal-site/blob/main/intro.md", content: "Kamal", headings: [] }
      ]
    )

    with_stub_fetcher(kamal_result) do
      assert_difference -> { Library.count }, 1 do
        ProcessCrawlRequestJob.perform_now(second_request)
      end
    end

    first_library.reload
    second_library = second_request.reload.library

    assert_equal "laravel", first_library.slug
    refute_equal first_library.id, second_library.id
    assert_equal "kamal-site", second_library.slug
    refute_includes second_library.aliases, "laravel"
  end

  test "reuses canonical library for git docs repos when product slug differs from repo name" do
    existing = Library.create!(
      account: @account,
      namespace: "act",
      name: "act",
      slug: "act",
      display_name: "Act",
      homepage_url: "https://github.com/nektos/act-docs",
      aliases: [ "act" ]
    )

    crawl_request = CrawlRequest.create!(
      creator: @user,
      url: "https://github.com/nektos/act-docs",
      source_type: "github",
      status: "pending"
    )

    result = CrawlResult.new(
      slug: "act",
      namespace: "nektos",
      name: "act-docs",
      display_name: "Act",
      homepage_url: "https://github.com/nektos/act-docs",
      aliases: [ "act", "act-docs", "nektos/act-docs" ],
      version: "latest",
      pages: [
        { page_uid: "intro", path: "intro.md", title: "Intro",
          url: "https://github.com/nektos/act-docs/blob/main/intro.md", content: "Act docs", headings: [] }
      ]
    )

    with_stub_fetcher(result) do
      assert_no_difference -> { Library.count } do
        ProcessCrawlRequestJob.perform_now(crawl_request)
      end
    end

    assert_equal existing.id, crawl_request.reload.library_id
    assert crawl_request.library.library_sources.exists?(url: "https://github.com/nektos/act-docs")
  end

  test "canonical metadata overrides correct existing library metadata on recrawl" do
    existing = Library.create!(
      account: @account,
      namespace: "nektos",
      name: "act-docs",
      slug: "nektos-act-docs",
      display_name: "Act Docs",
      homepage_url: "https://github.com/nektos/act-docs",
      aliases: [ "act-docs", "nektos/act-docs" ]
    )
    existing.library_sources.create!(
      url: "https://github.com/nektos/act-docs",
      source_type: "github",
      active: true,
      primary: true
    )

    crawl_request = CrawlRequest.create!(
      creator: @user,
      url: "https://github.com/nektos/act-docs",
      source_type: "github",
      status: "pending",
      metadata: {
        "canonical_slug" => "act",
        "canonical_display_name" => "Act"
      }
    )

    result = CrawlResult.new(
      slug: "nektos-act-docs",
      namespace: "nektos",
      name: "act-docs",
      display_name: "Act Docs",
      homepage_url: "https://github.com/nektos/act-docs",
      aliases: [ "act-docs", "nektos/act-docs" ],
      version: "latest",
      pages: [
        { page_uid: "intro", path: "intro.md", title: "Intro",
          url: "https://github.com/nektos/act-docs/blob/main/intro.md", content: "Act docs", headings: [] }
      ]
    )

    with_stub_fetcher(result) do
      assert_no_difference -> { Library.count } do
        ProcessCrawlRequestJob.perform_now(crawl_request)
      end
    end

    library = crawl_request.reload.library
    assert_equal existing.id, library.id
    assert_equal "act", library.slug
    assert_equal "Act", library.display_name
    assert_includes library.aliases, "act"
  end

  test "canonical metadata reassigns an existing source onto the canonical library" do
    canonical = Library.create!(
      account: @account,
      namespace: "act",
      name: "act",
      slug: "act",
      display_name: "Act",
      homepage_url: "https://github.com/nektos/act-docs",
      aliases: [ "act" ]
    )
    wrong = Library.create!(
      account: @account,
      namespace: "nektos",
      name: "act-docs",
      slug: "nektos-act-docs",
      display_name: "Act Docs",
      homepage_url: "https://github.com/nektos/act-docs",
      aliases: [ "act-docs", "nektos/act-docs" ]
    )
    source = wrong.library_sources.create!(
      url: "https://github.com/nektos/act-docs",
      source_type: "github",
      active: true,
      primary: true
    )

    crawl_request = CrawlRequest.create!(
      creator: @user,
      url: "https://github.com/nektos/act-docs",
      source_type: "github",
      status: "pending",
      metadata: {
        "canonical_slug" => "act",
        "canonical_display_name" => "Act"
      }
    )

    result = CrawlResult.new(
      slug: "nektos-act-docs",
      namespace: "nektos",
      name: "act-docs",
      display_name: "Act Docs",
      homepage_url: "https://github.com/nektos/act-docs",
      aliases: [ "act-docs", "nektos/act-docs" ],
      version: "latest",
      pages: [
        { page_uid: "intro", path: "intro.md", title: "Intro",
          url: "https://github.com/nektos/act-docs/blob/main/intro.md", content: "Act docs", headings: [] }
      ]
    )

    with_stub_fetcher(result) do
      assert_no_difference -> { Library.count } do
        ProcessCrawlRequestJob.perform_now(crawl_request)
      end
    end

    assert_equal canonical.id, crawl_request.reload.library_id
    assert_equal canonical.id, source.reload.library_id
  end

  test "canonical metadata reassigns a source onto the canonical library without duplicating primary sources" do
    canonical = Library.create!(
      account: @account,
      namespace: "redis",
      name: "redis",
      slug: "redis",
      display_name: "Redis",
      homepage_url: "https://github.com/redis/redis",
      aliases: [ "redis" ]
    )
    primary_source = canonical.library_sources.create!(
      url: "https://github.com/redis/redis",
      source_type: "github",
      active: true,
      primary: true
    )

    wrong = Library.create!(
      account: @account,
      namespace: "redis",
      name: "docs",
      slug: "redis-docs",
      display_name: "Redis",
      homepage_url: "https://github.com/redis/docs",
      aliases: [ "redis", "redis/docs", "redisdocs" ]
    )
    docs_source = wrong.library_sources.create!(
      url: "https://github.com/redis/docs",
      source_type: "github",
      active: true,
      primary: true
    )

    crawl_request = CrawlRequest.create!(
      creator: @user,
      url: "https://github.com/redis/docs",
      source_type: "github",
      status: "pending",
      metadata: {
        "canonical_slug" => "redis",
        "canonical_display_name" => "Redis"
      }
    )

    result = CrawlResult.new(
      slug: "redis-docs",
      namespace: "redis",
      name: "docs",
      display_name: "Redis",
      homepage_url: "https://github.com/redis/docs",
      aliases: [ "redis", "redis/docs", "redisdocs" ],
      version: "latest",
      pages: [
        {
          page_uid: "intro",
          path: "intro.md",
          title: "Intro",
          url: "https://github.com/redis/docs/blob/main/intro.md",
          content: "Redis docs",
          headings: []
        }
      ]
    )

    with_stub_fetcher(result) do
      assert_no_difference -> { Library.count } do
        ProcessCrawlRequestJob.perform_now(crawl_request)
      end
    end

    assert_equal canonical.id, crawl_request.reload.library_id
    assert_equal canonical.id, docs_source.reload.library_id
    assert_equal false, docs_source.primary
    assert_equal true, primary_source.reload.primary
    assert_equal 1, canonical.library_sources.where(primary: true).count
  end

  test "does not merge git libraries that share an owner" do
    rust_result = CrawlResult.new(
      slug: "rust",
      namespace: "rust-lang",
      name: "rust",
      display_name: "Rust",
      homepage_url: "https://github.com/rust-lang/rust",
      aliases: [ "rust", "rust-lang/rust" ],
      version: "1.0.0",
      pages: [
        { page_uid: "intro", path: "intro.md", title: "Intro",
          url: "https://github.com/rust-lang/rust/blob/main/intro.md", content: "Rust", headings: [] }
      ]
    )

    with_stub_fetcher(rust_result) do
      ProcessCrawlRequestJob.perform_now(@crawl_request)
    end

    first_library = @crawl_request.reload.library

    second_request = CrawlRequest.create!(
      creator: @user,
      url: "https://github.com/rust-lang/cargo",
      source_type: "github",
      status: "pending"
    )
    cargo_result = CrawlResult.new(
      slug: "cargo",
      namespace: "rust-lang",
      name: "cargo",
      display_name: "Cargo",
      homepage_url: "https://github.com/rust-lang/cargo",
      aliases: [ "cargo", "rust-lang/cargo" ],
      version: "1.0.0",
      pages: [
        { page_uid: "intro", path: "intro.md", title: "Intro",
          url: "https://github.com/rust-lang/cargo/blob/main/intro.md", content: "Cargo", headings: [] }
      ]
    )

    with_stub_fetcher(cargo_result) do
      assert_difference -> { Library.count }, 1 do
        ProcessCrawlRequestJob.perform_now(second_request)
      end
    end

    first_library.reload
    second_library = second_request.reload.library

    refute_equal first_library.id, second_library.id
    assert_equal "rust", first_library.slug
    assert_equal "cargo", second_library.slug
  end

  test "creates separate libraries for git repos with the same repo name under different owners" do
    first_result = CrawlResult.new(
      slug: "log",
      namespace: "charmbracelet",
      name: "log",
      display_name: "Charm Log",
      homepage_url: "https://github.com/charmbracelet/log",
      aliases: [ "log", "charmbracelet/log" ],
      version: "1.0.0",
      pages: [
        { page_uid: "intro", path: "intro.md", title: "Intro",
          url: "https://github.com/charmbracelet/log/blob/main/intro.md", content: "Charm", headings: [] }
      ]
    )

    with_stub_fetcher(first_result) do
      ProcessCrawlRequestJob.perform_now(@crawl_request)
    end

    second_request = CrawlRequest.create!(
      creator: @user,
      url: "https://github.com/rust-lang/log",
      source_type: "github",
      status: "pending"
    )
    second_result = CrawlResult.new(
      slug: "log",
      namespace: "rust-lang",
      name: "log",
      display_name: "Rust Log",
      homepage_url: "https://github.com/rust-lang/log",
      aliases: [ "log", "rust-lang/log" ],
      version: "0.4.29",
      pages: [
        { page_uid: "intro", path: "intro.md", title: "Intro",
          url: "https://github.com/rust-lang/log/blob/master/intro.md", content: "Rust log", headings: [] }
      ]
    )

    with_stub_fetcher(second_result) do
      assert_difference -> { Library.count }, 1 do
        ProcessCrawlRequestJob.perform_now(second_request)
      end
    end

    first_library = @crawl_request.reload.library
    second_library = second_request.reload.library

    refute_equal first_library.id, second_library.id
    assert_equal "log", first_library.slug
    assert_equal "rust-lang-log", second_library.slug
    assert_equal "rust-lang", second_library.namespace
    assert_equal "log", second_library.name
  end

  test "reuses the attached library and preserves locked metadata on recrawl" do
    existing = Library.create!(
      account: @account,
      namespace: "laravel",
      name: "laravel",
      display_name: "Laravel",
      homepage_url: "https://laravel.com/docs",
      aliases: [ "laravel" ],
      metadata_locked: true
    )
    @crawl_request.update!(library: existing)

    result = CrawlResult.new(
      namespace: "laravel",
      name: "docs",
      display_name: "Docs",
      homepage_url: "https://github.com/laravel/docs",
      aliases: [ "docs" ],
      version: nil,
      pages: [
        { page_uid: "intro", path: "intro.md", title: "Intro",
          url: "https://github.com/laravel/docs/blob/12.x/intro.md", content: "Hello", headings: [] }
      ]
    )

    with_stub_fetcher(result) do
      assert_no_difference -> { Library.count } do
        ProcessCrawlRequestJob.perform_now(@crawl_request)
      end
    end

    library = @crawl_request.reload.library
    assert_equal existing.id, library.id
    assert_equal "Laravel", library.display_name
    assert_equal "https://laravel.com/docs", library.homepage_url
    assert_includes library.aliases, "laravel"
    refute_includes library.aliases, "docs", "generic names like 'docs' must not be stored as aliases"
  end

  test "imports library into the seeded system account" do
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
      ProcessCrawlRequestJob.perform_now(@crawl_request)
    end

    library = @crawl_request.reload.library
    assert_not_nil library
    assert_equal Account.system, library.account
    assert_equal false, library.account.personal
  end

  test "re-crawl replaces all pages with fresh content" do
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
    original_page_id = version.pages.find_by(page_uid: "intro").id

    # Re-crawl — pages are deleted and recreated
    cr2 = CrawlRequest.create!(creator: @user, url: "https://example.com/llms.txt", source_type: "llms_txt", status: "pending")
    with_stub_fetcher(result) { ProcessCrawlRequestJob.perform_now(cr2) }

    version.reload
    assert_equal 1, version.pages.count
    new_page = version.pages.find_by(page_uid: "intro")
    assert_not_equal original_page_id, new_page.id, "Page should be recreated on recrawl"
    assert_equal "Hello world", new_page.description
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

    cr2 = CrawlRequest.create!(creator: @user, url: "https://example.com/llms.txt", source_type: "llms_txt", status: "pending")
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

    cr2 = CrawlRequest.create!(creator: @user, url: "https://example.com/llms.txt", source_type: "llms_txt", status: "pending")

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
