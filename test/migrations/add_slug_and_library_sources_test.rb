# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20260315102000_add_slug_and_library_sources")

class AddSlugAndLibrarySourcesTest < ActiveSupport::TestCase
  LibraryRow = Struct.new(:id, :namespace, :name, keyword_init: true)

  setup do
    @migration = AddSlugAndLibrarySources.new
  end

  test "backfill slug disambiguates colliding preferred names" do
    taken_slugs = Set.new

    first = @migration.send(
      :backfill_slug,
      LibraryRow.new(id: 1, namespace: "foo", name: "react"),
      taken_slugs
    )
    second = @migration.send(
      :backfill_slug,
      LibraryRow.new(id: 2, namespace: "bar", name: "react"),
      taken_slugs
    )

    assert_equal "react", first
    assert_equal "bar-react", second
  end

  test "backfill slug disambiguates repeated generic docs repos" do
    taken_slugs = Set.new

    first = @migration.send(
      :backfill_slug,
      LibraryRow.new(id: 1, namespace: "laravel", name: "docs"),
      taken_slugs
    )
    second = @migration.send(
      :backfill_slug,
      LibraryRow.new(id: 2, namespace: "laravel", name: "reference"),
      taken_slugs
    )

    assert_equal "laravel", first
    assert_equal "laravel-reference", second
  end
end
