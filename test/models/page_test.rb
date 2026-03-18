# frozen_string_literal: true

require "test_helper"

class PageTest < ActiveSupport::TestCase
  fixtures :accounts, :libraries, :versions, :pages

  test "valid page" do
    page = Page.new(
      version: versions(:nextjs_stable),
      page_uid: "pg_new_unique_id",
      path: "app/new-page.md",
      title: "New Page"
    )
    assert page.valid?
  end

  test "requires page_uid" do
    page = Page.new(version: versions(:nextjs_stable), path: "app/test.md", title: "Test")
    assert_not page.valid?
    assert page.errors[:page_uid].present?
  end

  test "requires path" do
    page = Page.new(version: versions(:nextjs_stable), page_uid: "pg_test_1", title: "Test")
    assert_not page.valid?
    assert page.errors[:path].present?
  end

  test "requires title" do
    page = Page.new(version: versions(:nextjs_stable), page_uid: "pg_test_1", path: "app/test.md")
    assert_not page.valid?
    assert page.errors[:title].present?
  end

  test "page_uid is unique per version" do
    # installation fixture already exists
    duplicate = Page.new(
      version: versions(:nextjs_stable),
      page_uid: "pg_install_001",
      path: "app/other.md",
      title: "Other"
    )
    assert_not duplicate.valid?
    assert duplicate.errors[:page_uid].present?
  end

  test "same page_uid allowed on different versions" do
    page = Page.new(
      version: versions(:rails_stable),
      page_uid: "pg_install_001",
      path: "getting-started.md",
      title: "Getting Started"
    )
    assert page.valid?
  end

  test "belongs to version" do
    page = pages(:installation)
    assert_equal versions(:nextjs_stable), page.version
  end

  test "search_content uses the stored search_tsvector column" do
    sql = Page.search_content("install").to_sql

    assert_includes sql, "search_tsvector"
  end

  test "persists oversized page content without overflowing search_tsvector" do
    huge_description = Array.new(120_000) { |i| "tok#{i}" }.join(" ")

    page = Page.new(
      version: versions(:nextjs_stable),
      page_uid: "pg_huge_search_index",
      path: "examples/huge.ipynb",
      title: "Huge Notebook",
      description: huge_description
    )

    assert_nothing_raised do
      page.save!
    end

    page.reload
    assert_operator page.description.bytesize, :>, 1_000_000
    assert_includes Page.search_content("tok100").pluck(:id), page.id
  end
end
