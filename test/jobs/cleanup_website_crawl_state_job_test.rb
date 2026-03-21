# frozen_string_literal: true

require "test_helper"

class CleanupWebsiteCrawlStateJobTest < ActiveSupport::TestCase
  setup do
    _identity, _account, user = create_tenant

    @expired_failed_request = CrawlRequest.create!(
      creator: user,
      url: "https://example.com/failed",
      source_type: "website",
      status: "failed",
      completed_at: 5.days.ago
    )
    @expired_failed_crawl = WebsiteCrawl.create!(
      crawl_request: @expired_failed_request,
      runner: "ruby",
      status: "failed",
      completed_at: 5.days.ago
    )
    @expired_failed_url = @expired_failed_crawl.crawl_urls.create!(
      url: "https://example.com/failed",
      normalized_url: "https://example.com/failed"
    )
    @expired_failed_crawl.crawl_pages.create!(
      website_crawl_url: @expired_failed_url,
      page_uid: "failed",
      path: "failed.md",
      title: "Failed",
      url: "https://example.com/failed",
      content: "staged failed content"
    )

    @recent_cancelled_request = CrawlRequest.create!(
      creator: user,
      url: "https://example.com/cancelled",
      source_type: "website",
      status: "cancelled",
      completed_at: 1.hour.ago
    )
    @recent_cancelled_crawl = WebsiteCrawl.create!(
      crawl_request: @recent_cancelled_request,
      runner: "ruby",
      status: "cancelled",
      completed_at: 1.hour.ago
    )
    @recent_cancelled_url = @recent_cancelled_crawl.crawl_urls.create!(
      url: "https://example.com/cancelled",
      normalized_url: "https://example.com/cancelled"
    )
    @recent_cancelled_crawl.crawl_pages.create!(
      website_crawl_url: @recent_cancelled_url,
      page_uid: "cancelled",
      path: "cancelled.md",
      title: "Cancelled",
      url: "https://example.com/cancelled",
      content: "staged cancelled content"
    )
  end

  test "purges staged rows for expired failed and cancelled crawls but keeps crawl history" do
    assert_difference -> { WebsiteCrawlPage.count }, -1 do
      assert_difference -> { WebsiteCrawlUrl.count }, -1 do
        assert_no_difference -> { WebsiteCrawl.count } do
          CleanupWebsiteCrawlStateJob.perform_now
        end
      end
    end

    assert_equal 0, @expired_failed_crawl.reload.crawl_pages.count
    assert_equal 0, @expired_failed_crawl.reload.crawl_urls.count
    assert_equal "failed", @expired_failed_crawl.status

    assert_equal 1, @recent_cancelled_crawl.reload.crawl_pages.count
    assert_equal 1, @recent_cancelled_crawl.reload.crawl_urls.count
    assert_equal "cancelled", @recent_cancelled_crawl.status
  end
end
