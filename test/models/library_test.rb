# frozen_string_literal: true

require "test_helper"

class LibraryTest < ActiveSupport::TestCase
  fixtures :accounts, :libraries, :versions, :pages

  test "valid library" do
    library = Library.new(
      account: accounts(:personal),
      namespace: "vercel",
      name: "somepkg",
      display_name: "Some Package"
    )
    assert library.valid?
  end

  test "requires namespace" do
    library = Library.new(name: "nextjs", display_name: "Next.js", account: accounts(:personal))
    assert_not library.valid?
    assert library.errors[:namespace].present?
  end

  test "requires name" do
    library = Library.new(namespace: "vercel", display_name: "Next.js", account: accounts(:personal))
    assert_not library.valid?
    assert library.errors[:name].present?
  end

  test "requires display_name" do
    library = Library.new(namespace: "vercel", name: "nextjs", account: accounts(:personal))
    assert_not library.valid?
    assert library.errors[:display_name].present?
  end

  test "namespace + name is unique" do
    # nextjs fixture already exists with namespace: vercel, name: nextjs
    duplicate = Library.new(
      account: accounts(:organization),
      namespace: "vercel",
      name: "nextjs",
      display_name: "Next.js Duplicate"
    )
    assert_not duplicate.valid?
    assert duplicate.errors[:namespace].present?
  end

  test "name must be path-safe slug" do
    library = Library.new(
      account: accounts(:personal),
      namespace: "vercel",
      name: "next.js",
      display_name: "Next.js"
    )
    assert_not library.valid?
    assert library.errors[:name].present?
  end

  test "namespace must be path-safe slug" do
    library = Library.new(
      account: accounts(:personal),
      namespace: "Vercel Inc",
      name: "nextjs",
      display_name: "Next.js"
    )
    assert_not library.valid?
    assert library.errors[:namespace].present?
  end

  test "name allows lowercase alphanumeric and hyphens" do
    library = Library.new(
      account: accounts(:personal),
      namespace: "my-org",
      name: "my-lib-2",
      display_name: "My Lib 2"
    )
    assert library.valid?
  end

  test "search by query" do
    results = Library.search_by_query("next")
    assert results.any?
    assert_includes results.map(&:name), "nextjs"
  end

  # -- Library.resolve --------------------------------------------------------

  test "resolve finds library by alias" do
    lib = Library.resolve("next.js")
    assert_equal "nextjs", lib.name
  end

  test "resolve finds library by alias (short form)" do
    lib = Library.resolve("next")
    assert_equal "nextjs", lib.name
  end

  test "resolve falls back to full-text search" do
    lib = Library.resolve("nextjs")
    assert_equal "nextjs", lib.name
  end

  test "resolve returns nil for unknown query" do
    assert_nil Library.resolve("nonexistent-library-xyz")
  end

  test "populate_slug defaults to name when slug is blank" do
    library = Library.create!(
      account: accounts(:personal),
      namespace: "vercel",
      name: "nextjs-docs",
      aliases: [ "next", "next.js" ],
      display_name: "Next.js Docs"
    )

    assert_equal "nextjs-docs", library.slug
  end

  test "slug is unique" do
    duplicate = Library.new(
      account: accounts(:organization),
      namespace: "another-org",
      name: "another-lib",
      slug: "nextjs",
      display_name: "Another Library"
    )

    assert_not duplicate.valid?
    assert duplicate.errors[:slug].present?
  end

  # -- Library#best_version ---------------------------------------------------

  test "best_version returns nil for library with no versions" do
    lib = Library.new(
      account: accounts(:personal),
      namespace: "test-bv-#{SecureRandom.hex(4)}",
      name: "empty",
      display_name: "Empty"
    )
    lib.save!
    assert_nil lib.best_version
  end

  test "best_version returns requested version when it exists" do
    lib = libraries(:nextjs)
    lib.versions.load # eager load
    v = lib.best_version(requested: "17.0.0-canary.1")
    assert_equal "17.0.0-canary.1", v.version
  end

  test "best_version ignores unknown requested version" do
    lib = libraries(:nextjs)
    lib.versions.load
    v = lib.best_version(requested: "99.0.0")
    # Falls back to default or richest
    assert_not_nil v
    assert_not_equal "99.0.0", v.version
  end

  test "best_version prefers default version when it has pages" do
    lib = libraries(:nextjs)
    lib.versions.includes(:pages).load
    v = lib.best_version
    assert_equal "16.1.6", v.version # default_version with pages
  end

  test "best_version prefers richest version when it has 3x more pages than default" do
    lib = libraries(:nextjs)
    rich_version = lib.versions.find_by(version: "17.0.0-canary.1")

    # Add 7 pages to canary to exceed 3x threshold (default has 2, need >6)
    7.times do |i|
      rich_version.pages.create!(
        page_uid: "pg_canary_#{SecureRandom.hex(4)}",
        path: "canary/page-#{i}.md",
        title: "Canary Page #{i}",
        url: "https://nextjs.org/docs/canary/page-#{i}",
        bytes: 1000
      )
    end

    lib.versions.includes(:pages).reload
    v = lib.best_version
    assert_equal "17.0.0-canary.1", v.version
  end
end
