# frozen_string_literal: true

require "test_helper"

class ProcessWebsiteCrawlJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  RunnerStub = Struct.new(:snapshots, :error, :ready, :calls, keyword_init: true) do
    def initialize(**attributes)
      super(ready: true, calls: [], snapshots: [], **attributes)
    end

    def fetch_batch(crawl_request, urls, on_progress: nil)
      calls << [ crawl_request, urls, on_progress ]
      raise error if error

      snapshots
    end

    def ready?
      ready
    end
  end

  setup do
    _identity, @account, @user = create_tenant
    @crawl_request = CrawlRequest.create!(
      creator: @user,
      url: "https://example.com/docs",
      source_type: "website",
      status: "pending"
    )
    clear_enqueued_jobs
  end

  teardown do
    FileUtils.rm_rf(DocsBundle.storage_root)
  end

  test "processes website crawls through the ruby website domain path" do
    website_crawl = WebsiteCrawl.create!(crawl_request: @crawl_request, runner: "ruby")
    ruby_runner = RunnerStub.new(
      snapshots: [
        {
          requested_url: "https://example.com/docs",
          url: "https://example.com/docs",
          page: {
            page_uid: "docs",
            path: "docs.md",
            title: "Example Docs",
            url: "https://example.com/docs",
            content: "Website documentation",
            headings: [ "Index" ]
          },
          links: []
        }
      ]
    )

    with_runner_stubs(ruby_runner: ruby_runner) do
      assert_difference -> { Library.count }, 1 do
        assert_difference -> { Version.count }, 1 do
          assert_difference -> { Page.count }, 1 do
            ProcessWebsiteCrawlJob.perform_now(website_crawl)
          end
        end
      end
    end

    @crawl_request.reload
    website_crawl.reload

    assert_equal "completed", @crawl_request.status
    assert_equal "completed", website_crawl.status
    assert_equal 0, website_crawl.crawl_urls.count
    assert_equal 0, website_crawl.crawl_pages.count
    assert_equal "Example", @crawl_request.library.display_name
    assert_equal 1, ruby_runner.calls.size
  end

  test "promotes auto website crawls to node and continues fetching there" do
    website_crawl = WebsiteCrawl.create!(crawl_request: @crawl_request, runner: "auto")
    ruby_runner = RunnerStub.new(
      snapshots: [
        {
          requested_url: "https://example.com/docs",
          url: "https://example.com/docs",
          page: {
            page_uid: "docs",
            path: "docs.md",
            title: "Example Docs",
            url: "https://example.com/docs",
            content: "You need to enable JavaScript to run this app.",
            headings: []
          },
          links: []
        }
      ]
    )
    node_runner = RunnerStub.new(
      snapshots: [
        {
          requested_url: "https://example.com/docs",
          url: "https://example.com/docs",
          page: {
            page_uid: "docs",
            path: "docs.md",
            title: "Example Docs",
            url: "https://example.com/docs",
            content: "Rendered documentation",
            headings: [ "Index" ]
          },
          links: []
        }
      ]
    )

    with_runner_stubs(ruby_runner: ruby_runner, node_runner: node_runner) do
      ProcessWebsiteCrawlJob.perform_now(website_crawl)
    end

    @crawl_request.reload
    website_crawl.reload

    assert_equal "completed", @crawl_request.status
    assert_equal "completed", website_crawl.status
    assert_equal "node", website_crawl.runner
    assert_equal 1, ruby_runner.calls.size
    assert_equal 1, node_runner.calls.size
  end

  test "marks both website crawl and crawl request as failed on domain errors" do
    website_crawl = WebsiteCrawl.create!(crawl_request: @crawl_request, runner: "ruby")
    ruby_runner = RunnerStub.new(error: RuntimeError.new("Website fetch failed"))
    with_runner_stubs(ruby_runner: ruby_runner) do
      ProcessWebsiteCrawlJob.perform_now(website_crawl)
    end

    @crawl_request.reload
    website_crawl.reload

    assert_equal "failed", @crawl_request.status
    assert_equal "failed", website_crawl.status
    assert_includes @crawl_request.error_message, "Website fetch failed"
    assert_includes website_crawl.error_message, "Website fetch failed"
  end

  test "skips duplicate processing when website crawl is already processing" do
    website_crawl = WebsiteCrawl.create!(crawl_request: @crawl_request, runner: "ruby")
    website_crawl.update!(status: "processing")
    @crawl_request.begin_processing!
    ruby_runner = RunnerStub.new

    with_runner_stubs(ruby_runner: ruby_runner) do
      ProcessWebsiteCrawlJob.perform_now(website_crawl)
    end

    assert_empty ruby_runner.calls
  end

  test "marks website crawl cancelled when parent request is cancelled before processing" do
    website_crawl = WebsiteCrawl.create!(crawl_request: @crawl_request, runner: "ruby")
    @crawl_request.mark_cancelled

    assert_no_difference -> { Library.count } do
      ProcessWebsiteCrawlJob.perform_now(website_crawl)
    end

    website_crawl.reload
    assert_equal "cancelled", website_crawl.status
  end

  test "preserves cancellation when no page content was stored yet" do
    website_crawl = WebsiteCrawl.create!(crawl_request: @crawl_request, runner: "ruby")
    ruby_runner = RunnerStub.new(
      snapshots: []
    )
    ruby_runner.define_singleton_method(:fetch_batch) do |crawl_request, urls, on_progress: nil|
      calls << [ crawl_request, urls, on_progress ]
      crawl_request.mark_cancelled
      []
    end

    with_runner_stubs(ruby_runner: ruby_runner) do
      ProcessWebsiteCrawlJob.perform_now(website_crawl)
    end

    @crawl_request.reload
    website_crawl.reload

    assert_equal "cancelled", @crawl_request.status
    assert_equal "cancelled", website_crawl.status
  end

  test "resumes after transient website errors without reprocessing completed urls" do
    website_crawl = WebsiteCrawl.create!(crawl_request: @crawl_request, runner: "ruby")
    seed_url = "https://example.com/docs"
    next_url = "https://example.com/docs/getting-started"
    website_crawl.crawl_urls.create!(url: seed_url, normalized_url: seed_url)
    website_crawl.crawl_urls.create!(url: next_url, normalized_url: next_url)

    attempts_by_url = Hash.new(0)
    test_case = self
    ruby_runner = RunnerStub.new

    ruby_runner.define_singleton_method(:fetch_batch) do |crawl_request, urls, on_progress: nil|
      calls << [ crawl_request, urls, on_progress ]
      requested_url = urls.fetch(0)
      attempts_by_url[requested_url] += 1

      case requested_url
      when seed_url
        [
          {
            requested_url: requested_url,
            url: requested_url,
            page: {
              page_uid: "docs",
              path: "docs.md",
              title: "Example Docs",
              url: requested_url,
              content: "Website documentation",
              headings: [ "Index" ]
            },
            links: [ next_url ]
          }
        ]
      when next_url
        if attempts_by_url[requested_url] == 1
          raise DocsFetcher::TransientFetchError, "Temporary website fetch failure"
        end

        test_case.assert_equal "processing", WebsiteCrawl.find(website_crawl.id).status

        [
          {
            requested_url: requested_url,
            url: requested_url,
            page: {
              page_uid: "docs-getting-started",
              path: "docs-getting-started.md",
              title: "Example Docs",
              url: requested_url,
              content: "Getting started",
              headings: [ "Getting Started" ]
            },
            links: []
          }
        ]
      else
        test_case.flunk("Unexpected URL #{requested_url.inspect}")
      end
    end

    with_runner_stubs(ruby_runner: ruby_runner) do
      ProcessWebsiteCrawlJob.perform_now(website_crawl)

      website_crawl.reload

      assert_equal "pending", website_crawl.status
      assert_equal [ [ seed_url ], [ next_url ] ], ruby_runner.calls.map { |_, urls, _| urls }
      assert_equal 1, enqueued_jobs.size

      resumed_job = enqueued_jobs.shift.except(:job, :args, :queue, :priority).deep_stringify_keys
      ActiveJob::Base.execute(resumed_job)
    end

    @crawl_request.reload
    website_crawl.reload

    assert_equal "completed", @crawl_request.status
    assert_equal "completed", website_crawl.status
    assert_equal [ [ seed_url ], [ next_url ], [ next_url ] ], ruby_runner.calls.map { |_, urls, _| urls }
  end

  test "deduplicates redirected pages and deconflicts colliding page_uids during publish" do
    website_crawl = WebsiteCrawl.create!(crawl_request: @crawl_request, runner: "node")
    seed_url = "https://example.com/docs"
    intro_url = "https://example.com/docs/introduction"
    switch_url = "https://example.com/docs/Switch"
    underscore_switch_url = "https://example.com/docs/_switch"
    colon_switch_url = "https://example.com/docs/:switch"

    node_runner = RunnerStub.new(
      snapshots: [
        {
          requested_url: seed_url,
          url: intro_url,
          page: {
            page_uid: "introduction",
            path: "introduction.md",
            title: "Introduction",
            url: intro_url,
            content: "Intro content",
            headings: [ "Introduction" ]
          },
          links: [ intro_url, switch_url, underscore_switch_url, colon_switch_url ]
        },
        {
          requested_url: intro_url,
          url: intro_url,
          page: {
            page_uid: "introduction",
            path: "introduction.md",
            title: "Introduction",
            url: intro_url,
            content: "Intro content",
            headings: [ "Introduction" ]
          },
          links: []
        },
        {
          requested_url: switch_url,
          url: switch_url,
          page: {
            page_uid: "switch",
            path: "switch.md",
            title: "Switch",
            url: switch_url,
            content: "Switch content",
            headings: [ "Switch" ]
          },
          links: []
        },
        {
          requested_url: underscore_switch_url,
          url: underscore_switch_url,
          page: {
            page_uid: "switch",
            path: "switch.md",
            title: "_switch",
            url: underscore_switch_url,
            content: "Underscore switch content",
            headings: [ "_switch" ]
          },
          links: []
        },
        {
          requested_url: colon_switch_url,
          url: colon_switch_url,
          page: {
            page_uid: "switch",
            path: "switch.md",
            title: ":switch",
            url: colon_switch_url,
            content: "Colon switch content",
            headings: [ ":switch" ]
          },
          links: []
        }
      ]
    )

    with_runner_stubs(ruby_runner: RunnerStub.new, node_runner: node_runner) do
      ProcessWebsiteCrawlJob.perform_now(website_crawl)
    end

    @crawl_request.reload
    website_crawl.reload

    assert_equal "completed", @crawl_request.status
    assert_equal "completed", website_crawl.status

    pages = @crawl_request.library.versions.find_by!(version: "latest").pages.order(:page_uid).to_a
    page_uids = pages.map(&:page_uid)

    assert_equal 4, pages.size
    assert_equal page_uids.uniq.size, page_uids.size
    assert_includes page_uids, "introduction"
    assert_equal 3, page_uids.grep(/\Aswitch(?:-|$)/).size
  end

  private

    def with_runner_stubs(ruby_runner:, node_runner: RunnerStub.new)
      original_ruby_new = DocsFetcher::Website::RubyRunner.method(:new)
      original_node_new = DocsFetcher::Website::NodeRunner.method(:new)

      DocsFetcher::Website::RubyRunner.define_singleton_method(:new) { ruby_runner }
      DocsFetcher::Website::NodeRunner.define_singleton_method(:new) { node_runner }

      yield
    ensure
      DocsFetcher::Website::RubyRunner.define_singleton_method(:new, original_ruby_new)
      DocsFetcher::Website::NodeRunner.define_singleton_method(:new, original_node_new)
    end
end
