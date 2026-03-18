# frozen_string_literal: true

require "test_helper"

class LibrarySourceTest < ActiveSupport::TestCase
  setup do
    _identity, account, _user = create_tenant(email: "library-source-#{SecureRandom.hex(4)}@example.com")
    @library = Library.create!(
      account: account,
      namespace: "laravel",
      name: "docs",
      slug: "laravel",
      display_name: "Laravel"
    )
  end

  test "normalizes github urls to canonical repo path" do
    source = @library.library_sources.create!(
      url: "https://github.com/laravel/docs/tree/12.x/",
      source_type: "github"
    )

    assert_equal "https://github.com/laravel/docs", source.url
  end

  test "find_matching reuses normalized github repo urls" do
    existing = @library.library_sources.create!(
      url: "https://github.com/laravel/docs/",
      source_type: "github"
    )

    match = LibrarySource.find_matching(
      url: "https://github.com/laravel/docs/tree/12.x",
      source_type: "github"
    )

    assert_equal existing.id, match.id
  end

  test "initializes version check schedule for primary version-checkable sources" do
    source = @library.library_sources.create!(
      url: "https://github.com/laravel/docs",
      source_type: "github",
      primary: true
    )

    assert source.version_checkable?
    assert_equal "normal", source.version_check_bucket
    assert_in_delta 7.days.from_now.to_f, source.next_version_check_at.to_f, 1.day.to_f
    assert_equal 0, source.consecutive_no_change_checks
  end

  test "initializes website version check schedule as cold by default" do
    source = @library.library_sources.create!(
      url: "https://docs.laravel.com",
      source_type: "website",
      primary: true
    )

    assert source.version_checkable?
    assert_equal "normal", source.version_check_bucket
    assert_in_delta 30.days.from_now.to_f, source.next_version_check_at.to_f, 1.day.to_f
  end

  test "version check due scope only includes primary version-checkable overdue sources" do
    due = @library.library_sources.create!(
      url: "https://github.com/laravel/docs",
      source_type: "github",
      primary: true,
      next_version_check_at: 1.hour.ago
    )
    @library.library_sources.create!(
      url: "https://github.com/laravel/docs-site",
      source_type: "github",
      primary: false,
      next_version_check_at: 1.hour.ago
    )
    other_library = Library.create!(
      account: @library.account,
      namespace: "laravel-website",
      name: "docs",
      slug: "laravel-website",
      display_name: "Laravel Website"
    )
    other_library.library_sources.create!(
      url: "https://docs.laravel.com",
      source_type: "website",
      primary: true,
      next_version_check_at: 1.hour.ago
    )

    assert_includes LibrarySource.version_check_due.to_a, due
    assert_equal 2, LibrarySource.version_check_due.count
  end
end
