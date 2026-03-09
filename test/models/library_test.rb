# frozen_string_literal: true

require "test_helper"

class LibraryTest < ActiveSupport::TestCase
  fixtures :accounts, :libraries

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
end
