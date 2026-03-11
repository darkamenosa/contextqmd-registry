# frozen_string_literal: true

require "test_helper"

class DocsFetcher::WebsiteTest < ActiveSupport::TestCase
  StubRunner = Struct.new(:result, :error, :ready, :calls, keyword_init: true) do
    def initialize(**attributes)
      super(ready: true, calls: [], **attributes)
    end

    def ready?
      ready
    end

    def fetch(crawl_request, on_progress: nil)
      calls << [ crawl_request, on_progress ]
      raise error if error

      result
    end
  end

  setup do
    @fetcher = DocsFetcher::Website::RubyRunner.new
  end

  # --- Delegation ---

  test "Website delegates to RubyRunner" do
    website = DocsFetcher::Website.new
    runner = website.send(:select_runner, Struct.new(:metadata).new({}))
    assert_instance_of DocsFetcher::Website::RubyRunner, runner
  end

  test "Website selects NodeRunner when crawl metadata requests it" do
    website = DocsFetcher::Website.new
    ruby_runner = StubRunner.new
    node_runner = StubRunner.new
    crawl_request = Struct.new(:metadata).new({ "website_runner" => "node" })

    website.define_singleton_method(:ruby_runner) { ruby_runner }
    website.define_singleton_method(:node_runner) { node_runner }

    assert_equal node_runner, website.send(:select_runner, crawl_request)
  end

  test "Website falls back to NodeRunner when Ruby crawler hits a javascript shell" do
    website = DocsFetcher::Website.new
    ruby_result = CrawlResult.new(
      namespace: "example",
      name: "example",
      display_name: "Example",
      homepage_url: "https://docs.example.com",
      aliases: [ "example" ],
      version: nil,
      pages: [
        {
          page_uid: "index",
          path: "index.md",
          title: "Example",
          url: "https://docs.example.com",
          content: "You need to enable JavaScript to run this app.",
          headings: []
        }
      ],
      complete: false
    )
    node_result = CrawlResult.new(
      namespace: "example",
      name: "example",
      display_name: "Example Docs",
      homepage_url: "https://docs.example.com",
      aliases: [ "example" ],
      version: nil,
      pages: [
        {
          page_uid: "guide",
          path: "guide.md",
          title: "Guide",
          url: "https://docs.example.com/guide",
          content: "# Guide\n\nReal rendered content.",
          headings: [ "Guide" ]
        }
      ],
      complete: false
    )
    ruby_runner = StubRunner.new(result: ruby_result)
    node_runner = StubRunner.new(result: node_result)
    crawl_request = Struct.new(:metadata).new({})
    progress_messages = []

    website.define_singleton_method(:ruby_runner) { ruby_runner }
    website.define_singleton_method(:node_runner) { node_runner }

    result = website.fetch(crawl_request, on_progress: ->(message, **_progress) { progress_messages << message })

    assert_equal node_result, result
    assert_equal 1, ruby_runner.calls.size
    assert_equal 1, node_runner.calls.size
    assert_includes progress_messages, "Retrying with browser-rendered crawl"
  end

  test "Website falls back to NodeRunner when Ruby crawler finds no content" do
    website = DocsFetcher::Website.new
    ruby_runner = StubRunner.new(
      error: DocsFetcher::PermanentFetchError.new("No content found at https://docs.example.com")
    )
    node_runner = StubRunner.new(
      result: CrawlResult.new(
        namespace: "example",
        name: "example",
        display_name: "Example Docs",
        homepage_url: "https://docs.example.com",
        aliases: [ "example" ],
        version: nil,
        pages: [
          {
            page_uid: "guide",
            path: "guide.md",
            title: "Guide",
            url: "https://docs.example.com/guide",
            content: "# Guide\n\nRendered docs.",
            headings: [ "Guide" ]
          }
        ],
        complete: false
      )
    )
    crawl_request = Struct.new(:metadata).new({})

    website.define_singleton_method(:ruby_runner) { ruby_runner }
    website.define_singleton_method(:node_runner) { node_runner }

    result = website.fetch(crawl_request)

    assert_equal "Example Docs", result.display_name
    assert_equal 1, ruby_runner.calls.size
    assert_equal 1, node_runner.calls.size
  end

  test "crawl keeps pages larger than one megabyte" do
    huge_body = ("Hello from docs. " * 80_000)
    html = "<html><body><main><h1>Huge Guide</h1><p>#{huge_body}</p></main></body></html>"
    seed_uri = URI.parse("https://example.com/docs/huge")

    @fetcher.instance_variable_set(:@domain, "example.com")
    @fetcher.instance_variable_set(:@scheme, "https")
    @fetcher.instance_variable_set(:@base_path, "/docs")

    @fetcher.define_singleton_method(:http_get_with_redirects) { |_uri| html }
    @fetcher.define_singleton_method(:discover_links) { |_doc, _uri| [] }
    @fetcher.define_singleton_method(:sleep) { |_duration| }

    pages = @fetcher.send(:crawl, seed_uri)

    assert_equal 1, pages.size
    assert_equal "Huge Guide", pages.first[:title]
    assert_operator pages.first[:content].bytesize, :>, 1_000_000
  end

  test "crawl is not capped at one thousand pages" do
    total_pages = 1001
    seed_uri = URI.parse("https://example.com/docs/page-0")
    html_by_url = {}

    total_pages.times do |index|
      current_url = "https://example.com/docs/page-#{index}"
      next_link = if index + 1 < total_pages
        %(<a href="https://example.com/docs/page-#{index + 1}">Next</a>)
      else
        ""
      end

      html_by_url[current_url] = <<~HTML
        <html>
          <body>
            <main>
              <h1>Page #{index}</h1>
              <p>Documentation page #{index}</p>
              #{next_link}
            </main>
          </body>
        </html>
      HTML
    end

    @fetcher.instance_variable_set(:@domain, "example.com")
    @fetcher.instance_variable_set(:@scheme, "https")
    @fetcher.instance_variable_set(:@base_path, "/docs")
    @fetcher.define_singleton_method(:sleep) { |_duration| }

    @fetcher.define_singleton_method(:http_get_with_redirects) do |uri|
      html_by_url.fetch(uri.to_s)
    end

    pages = @fetcher.send(:crawl, seed_uri)

    assert_equal total_pages, pages.size
    assert_equal "docs-page-1000.md", pages.last[:path]
  end

  test "crawl stops after configured max_pages" do
    seed_uri = URI.parse("https://example.com/docs/page-0")
    html_by_url = {
      "https://example.com/docs/page-0" => <<~HTML,
        <html>
          <body>
            <main>
              <h1>Page 0</h1>
              <p>Documentation page 0</p>
              <a href="https://example.com/docs/page-1">Next</a>
            </main>
          </body>
        </html>
      HTML
      "https://example.com/docs/page-1" => <<~HTML,
        <html>
          <body>
            <main>
              <h1>Page 1</h1>
              <p>Documentation page 1</p>
              <a href="https://example.com/docs/page-2">Next</a>
            </main>
          </body>
        </html>
      HTML
      "https://example.com/docs/page-2" => <<~HTML
        <html>
          <body>
            <main>
              <h1>Page 2</h1>
              <p>Documentation page 2</p>
            </main>
          </body>
        </html>
      HTML
    }

    @fetcher.instance_variable_set(:@domain, "example.com")
    @fetcher.instance_variable_set(:@scheme, "https")
    @fetcher.instance_variable_set(:@base_path, "/docs")
    @fetcher.instance_variable_set(:@max_pages, 1)
    @fetcher.define_singleton_method(:sleep) { |_duration| }

    @fetcher.define_singleton_method(:http_get_with_redirects) do |uri|
      html_by_url.fetch(uri.to_s)
    end

    pages = @fetcher.send(:crawl, seed_uri)

    assert_equal 1, pages.size
    assert_equal "Page 0", pages.first[:title]
  end

  # --- URL normalization ---

  test "normalize_url removes fragment" do
    normalized = @fetcher.send(:normalize_url, "https://example.com/docs/intro#section-1")
    assert_equal "https://example.com/docs/intro", normalized
  end

  test "normalize_url strips trailing slash" do
    normalized = @fetcher.send(:normalize_url, "https://example.com/docs/")
    assert_equal "https://example.com/docs", normalized
  end

  test "normalize_url downcases host" do
    normalized = @fetcher.send(:normalize_url, "https://EXAMPLE.COM/docs")
    assert_equal "https://example.com/docs", normalized
  end

  test "normalize_url uses root slash for empty path" do
    normalized = @fetcher.send(:normalize_url, "https://example.com")
    assert_equal "https://example.com/", normalized
  end

  # --- Base path computation ---

  test "compute_base_path returns / for root URL" do
    assert_equal "/", @fetcher.send(:compute_base_path, "/")
  end

  test "compute_base_path returns / for empty path" do
    assert_equal "/", @fetcher.send(:compute_base_path, "")
  end

  test "compute_base_path strips file extension and goes up a level" do
    assert_equal "/docs", @fetcher.send(:compute_base_path, "/docs/intro.html")
  end

  test "compute_base_path strips last segment for multi-segment paths" do
    assert_equal "/v2", @fetcher.send(:compute_base_path, "/v2/guides")
  end

  test "compute_base_path keeps single-segment paths as section root" do
    assert_equal "/docs", @fetcher.send(:compute_base_path, "/docs")
  end

  test "compute_base_path handles trailing slash" do
    assert_equal "/docs", @fetcher.send(:compute_base_path, "/docs/guides/")
  end

  # --- Link filtering ---

  test "same_domain checks host match" do
    @fetcher.instance_variable_set(:@domain, "example.com")

    assert @fetcher.send(:same_domain?, URI.parse("https://example.com/docs"))
    assert_not @fetcher.send(:same_domain?, URI.parse("https://other.com/docs"))
  end

  test "within_path_prefix allows all paths when base is root" do
    @fetcher.instance_variable_set(:@base_path, "/")

    assert @fetcher.send(:within_path_prefix?, URI.parse("https://example.com/anything"))
    assert @fetcher.send(:within_path_prefix?, URI.parse("https://example.com/deep/path"))
  end

  test "within_path_prefix restricts to prefix when base is not root" do
    @fetcher.instance_variable_set(:@base_path, "/docs/v2")

    assert @fetcher.send(:within_path_prefix?, URI.parse("https://example.com/docs/v2/intro"))
    assert @fetcher.send(:within_path_prefix?, URI.parse("https://example.com/docs/v2"))
    assert_not @fetcher.send(:within_path_prefix?, URI.parse("https://example.com/blog/post"))
  end

  # --- Skip URL logic ---

  test "skip_url skips image files" do
    assert @fetcher.send(:skip_url?, URI.parse("https://example.com/logo.png"))
    assert @fetcher.send(:skip_url?, URI.parse("https://example.com/photo.jpg"))
    assert @fetcher.send(:skip_url?, URI.parse("https://example.com/icon.svg"))
  end

  test "skip_url skips asset files" do
    assert @fetcher.send(:skip_url?, URI.parse("https://example.com/style.css"))
    assert @fetcher.send(:skip_url?, URI.parse("https://example.com/app.js"))
    assert @fetcher.send(:skip_url?, URI.parse("https://example.com/data.json"))
  end

  test "skip_url skips URLs with tracking parameters" do
    assert @fetcher.send(:skip_url?, URI.parse("https://example.com/page?utm_source=twitter"))
  end

  test "skip_url skips asset paths" do
    assert @fetcher.send(:skip_url?, URI.parse("https://example.com/assets/img/logo"))
    assert @fetcher.send(:skip_url?, URI.parse("https://example.com/static/docs/file"))
  end

  test "skip_url allows normal doc URLs" do
    assert_not @fetcher.send(:skip_url?, URI.parse("https://example.com/docs/getting-started"))
    assert_not @fetcher.send(:skip_url?, URI.parse("https://example.com/guides/intro"))
  end

  # --- Default website exclude path prefixes ---

  test "skip_url skips default excluded path prefixes" do
    assert @fetcher.send(:skip_url?, URI.parse("https://example.com/blog/post-1"))
    assert @fetcher.send(:skip_url?, URI.parse("https://example.com/changelog/v2"))
    assert @fetcher.send(:skip_url?, URI.parse("https://example.com/pricing/enterprise"))
    assert @fetcher.send(:skip_url?, URI.parse("https://example.com/login/"))
    assert @fetcher.send(:skip_url?, URI.parse("https://example.com/signup/step1"))
    assert @fetcher.send(:skip_url?, URI.parse("https://example.com/admin/dashboard"))
    assert @fetcher.send(:skip_url?, URI.parse("https://example.com/tag/ruby"))
    assert @fetcher.send(:skip_url?, URI.parse("https://example.com/category/tutorials"))
    assert @fetcher.send(:skip_url?, URI.parse("https://example.com/author/john"))
    assert @fetcher.send(:skip_url?, URI.parse("https://example.com/feed/rss"))
  end

  # --- Library-specific website exclude path prefixes ---

  test "skip_url applies library-specific exclude path prefixes" do
    @fetcher.instance_variable_set(:@crawl_rules, {
      "website_exclude_path_prefixes" => [ "/careers/", "/press/" ]
    })

    assert @fetcher.send(:skip_url?, URI.parse("https://example.com/careers/engineering"))
    assert @fetcher.send(:skip_url?, URI.parse("https://example.com/press/release-2024"))
    # Default excludes still work
    assert @fetcher.send(:skip_url?, URI.parse("https://example.com/blog/post-1"))
    # Non-excluded paths still allowed
    assert_not @fetcher.send(:skip_url?, URI.parse("https://example.com/docs/intro"))
  end

  # --- load_crawl_rules ---

  test "load_crawl_rules returns empty hash without library_id" do
    crawl_request = Struct.new(:library_id, :library).new(nil, nil)
    result = @fetcher.send(:load_crawl_rules, crawl_request)
    assert_equal({}, result)
  end

  test "max_pages_for returns nil by default" do
    crawl_request = Struct.new(:metadata).new({})

    assert_nil @fetcher.send(:max_pages_for, crawl_request)
  end

  test "max_pages_for parses positive metadata values" do
    crawl_request = Struct.new(:metadata).new({ "website_max_pages" => "3" })

    assert_equal 3, @fetcher.send(:max_pages_for, crawl_request)
  end

  test "max_pages_for ignores non-positive metadata values" do
    crawl_request = Struct.new(:metadata).new({ "website_max_pages" => "0" })

    assert_nil @fetcher.send(:max_pages_for, crawl_request)
  end

  # --- URL to page UID ---

  test "url_to_page_uid converts path to slug" do
    uid = @fetcher.send(:url_to_page_uid, URI.parse("https://example.com/docs/getting-started"))
    assert_equal "docs-getting-started", uid
  end

  test "url_to_page_uid returns index for root path" do
    uid = @fetcher.send(:url_to_page_uid, URI.parse("https://example.com/"))
    assert_equal "index", uid
  end

  test "url_to_page_uid strips file extensions" do
    uid = @fetcher.send(:url_to_page_uid, URI.parse("https://example.com/docs/intro.html"))
    assert_equal "docs-intro", uid
  end

  test "url_to_page_uid handles special characters" do
    uid = @fetcher.send(:url_to_page_uid, URI.parse("https://example.com/docs/C++_Guide"))
    assert_equal "docs-c-guide", uid
  end

  # --- Resolve URL ---

  test "resolve_url skips fragment-only links" do
    base = URI.parse("https://example.com/docs")
    assert_nil @fetcher.send(:resolve_url, "#section-1", base)
  end

  test "resolve_url skips javascript links" do
    base = URI.parse("https://example.com/docs")
    assert_nil @fetcher.send(:resolve_url, "javascript:void(0)", base)
  end

  test "resolve_url skips mailto links" do
    base = URI.parse("https://example.com/docs")
    assert_nil @fetcher.send(:resolve_url, "mailto:test@example.com", base)
  end

  test "resolve_url resolves relative URLs" do
    base = URI.parse("https://example.com/docs/intro")
    resolved = @fetcher.send(:resolve_url, "getting-started", base)
    assert_equal "https://example.com/docs/getting-started", resolved.to_s
  end

  test "resolve_url resolves absolute URLs" do
    base = URI.parse("https://example.com/docs/intro")
    resolved = @fetcher.send(:resolve_url, "/api/reference", base)
    assert_equal "https://example.com/api/reference", resolved.to_s
  end

  test "resolve_url strips fragment from resolved URL" do
    base = URI.parse("https://example.com/docs/")
    resolved = @fetcher.send(:resolve_url, "page#heading", base)
    assert_equal "https://example.com/docs/page", resolved.to_s
  end
end
