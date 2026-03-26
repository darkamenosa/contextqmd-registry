# frozen_string_literal: true

class WebsiteCrawlPageCollection
  include Enumerable

  def initialize(relation)
    @relation = relation
  end

  def each
    return enum_for(:each) unless block_given?

    relation.order(:id).in_batches(of: 1000, load: true) do |batch|
      batch.each do |page|
        # Yield an explicit hash so Enumerable consumers like each_with_index
        # always receive the page payload as a single object.
        yield({
          page_uid: page.page_uid,
          path: page.path,
          title: page.title,
          url: page.url,
          content: page.content,
          headings: page.headings
        })
      end
    end
  end

  def size
    relation.count
  end

  def first
    page = relation.order(:id).first
    return unless page

    {
      page_uid: page.page_uid,
      path: page.path,
      title: page.title,
      url: page.url,
      content: page.content,
      headings: page.headings
    }
  end

  private

    attr_reader :relation
end
