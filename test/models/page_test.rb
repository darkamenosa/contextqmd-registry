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

  test "search_content uses plain description in the search expression" do
    sql = Page.search_content("install").to_sql

    assert_includes sql, %(coalesce(("pages"."description")::text, ''))
    assert_not_includes sql, "left("
    assert_not_includes sql, "search_tsvector"
  end

  test "rejects descriptions exceeding 500_000 characters" do
    page = Page.new(
      version: versions(:nextjs_stable),
      page_uid: "pg_huge_description",
      path: "examples/huge.ipynb",
      title: "Huge Notebook",
      description: "x" * 500_001
    )

    assert_not page.valid?
    assert_includes page.errors[:description], "is too long (maximum is 500000 characters)"
  end
end
