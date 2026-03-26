require "test_helper"

class WebsiteCrawlPageCollectionTest < ActiveSupport::TestCase
  setup do
    _identity, _account, @user = create_tenant
  end

  test "each_with_index yields hashes for every staged page" do
    crawl_request = CrawlRequest.create!(
      url: "https://example.com/start",
      source_type: "website",
      creator: @user
    )
    website_crawl = WebsiteCrawl.create!(crawl_request: crawl_request, runner: "auto")

    140.times do |index|
      crawl_url = website_crawl.crawl_urls.create!(
        url: "https://example.com/pages/#{index}",
        normalized_url: "https://example.com/pages/#{index}"
      )
      website_crawl.crawl_pages.create!(
        website_crawl_url: crawl_url,
        page_uid: "page-#{index}",
        path: "page-#{index}.md",
        title: "Page #{index}",
        url: crawl_url.url,
        content: "Content #{index}",
        headings: [ "Heading #{index}" ]
      )
    end

    collection = WebsiteCrawlPageCollection.new(website_crawl.crawl_pages)
    rows = []

    collection.each_with_index do |page_data, index|
      rows << [ index, page_data ]
    end

    assert_equal 140, rows.size
    assert rows.all? { |_, page_data| page_data.is_a?(Hash) }

    later_row = rows.fetch(120).last
    assert_equal "page-120", later_row[:page_uid]
    assert_equal "Page 120", later_row[:title]
    assert_equal "https://example.com/pages/120", later_row[:url]
  end
end
