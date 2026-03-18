# frozen_string_literal: true

require "test_helper"

class CheckLibrarySourceJobTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  setup do
    @original_queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    clear_enqueued_jobs
    clear_performed_jobs

    @identity, account, _user = create_tenant(email: "check-source-#{SecureRandom.hex(4)}@example.com")
    @library = Library.create!(
      account: account,
      namespace: "check-source",
      name: "docs",
      slug: "check-source-docs",
      display_name: "Check Source Docs"
    )
    @source = @library.library_sources.create!(
      url: "https://git.example.com/team/repo",
      source_type: "git",
      primary: true,
      next_version_check_at: 1.hour.ago
    )
    @library.versions.create!(
      version: "1.0.0",
      channel: "stable",
      generated_at: 1.day.ago
    )
  end

  teardown do
    clear_enqueued_jobs
    clear_performed_jobs
    ActiveJob::Base.queue_adapter = @original_queue_adapter
  end

  test "creates a scheduled crawl request when a newer version is detected" do
    @source.claim_version_check!

    fetcher = Struct.new(:probe) do
      def probe_version(_url)
        probe
      end
    end.new({
      version: "1.1.0",
      ref: "v1.1.0",
      crawl_url: "https://git.example.com/team/repo"
    })

    original_for = DocsFetcher.method(:for)
    DocsFetcher.define_singleton_method(:for) { |_source_type| fetcher }
    begin
      assert_difference -> { CrawlRequest.count }, 1 do
        CheckLibrarySourceJob.perform_now(@source)
      end
    ensure
      DocsFetcher.define_singleton_method(:for, original_for)
    end

    crawl_request = CrawlRequest.order(:id).last
    assert_equal @source, crawl_request.library_source
    assert_equal @library, crawl_request.library
    assert_equal "git", crawl_request.source_type
    assert_equal "public", crawl_request.requested_bundle_visibility
    assert_equal "1.1.0", crawl_request.metadata["detected_version"]
    assert_equal "v1.1.0", crawl_request.metadata["detected_ref"]
    assert_equal CrawlRequest.system_identity, crawl_request.identity

    @source.reload
    assert_nil @source.version_check_claimed_at
    assert_equal 0, @source.consecutive_no_change_checks
    assert @source.last_version_change_at.present?
  end

  test "skips creating a duplicate crawl request for the same detected version" do
    @source.claim_version_check!
    CrawlRequest.create!(
      identity: @identity,
      library: @library,
      library_source: @source,
      url: @source.url,
      source_type: "git",
      requested_bundle_visibility: "public",
      metadata: {
        "refresh_reason" => "version_check",
        "detected_version" => "1.1.0",
        "detected_ref" => "v1.1.0"
      }
    )

    fetcher = Struct.new(:probe) do
      def probe_version(_url)
        probe
      end
    end.new({
      version: "1.1.0",
      ref: "v1.1.0",
      crawl_url: "https://git.example.com/team/repo"
    })

    original_for = DocsFetcher.method(:for)
    DocsFetcher.define_singleton_method(:for) { |_source_type| fetcher }
    begin
      assert_no_difference -> { CrawlRequest.count } do
        CheckLibrarySourceJob.perform_now(@source)
      end
    ensure
      DocsFetcher.define_singleton_method(:for, original_for)
    end
  end

  test "creates a scheduled crawl request for website content changes" do
    website_library = Library.create!(
      account: @library.account,
      namespace: "website-source",
      name: "docs",
      slug: "website-source-docs",
      display_name: "Website Source Docs"
    )
    website_source = website_library.library_sources.create!(
      url: "https://docs.example.com",
      source_type: "website",
      primary: true,
      next_version_check_at: 1.hour.ago,
      last_probe_signature: "old-signature"
    )
    website_source.claim_version_check!

    fetcher = Struct.new(:probe) do
      def probe_version(_url)
        probe
      end
    end.new({
      signature: "new-signature",
      crawl_url: "https://docs.example.com"
    })

    original_for = DocsFetcher.method(:for)
    DocsFetcher.define_singleton_method(:for) { |_source_type| fetcher }
    begin
      assert_difference -> { CrawlRequest.count }, 1 do
        CheckLibrarySourceJob.perform_now(website_source)
      end
    ensure
      DocsFetcher.define_singleton_method(:for, original_for)
    end

    crawl_request = CrawlRequest.order(:id).last
    assert_equal "content_check", crawl_request.metadata["refresh_reason"]
    assert_equal "new-signature", crawl_request.metadata["detected_signature"]

    website_source.reload
    assert_equal "new-signature", website_source.last_probe_signature
    assert website_source.last_version_change_at.present?
  end
end
