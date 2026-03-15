# frozen_string_literal: true

require "test_helper"

class LibrarySourceTest < ActiveSupport::TestCase
  test "normalizes github urls to canonical repo path" do
    account = Account.create!(name: "Library Source Test Account", personal: false)
    account.users.create!(name: "System", role: :system)
    library = Library.create!(
      account: account,
      namespace: "laravel",
      name: "docs",
      slug: "laravel",
      display_name: "Laravel"
    )

    source = library.library_sources.create!(
      url: "https://github.com/laravel/docs/tree/12.x/",
      source_type: "github"
    )

    assert_equal "https://github.com/laravel/docs", source.url
  end

  test "find_matching reuses normalized github repo urls" do
    account = Account.create!(name: "Library Source Match Account", personal: false)
    account.users.create!(name: "System", role: :system)
    library = Library.create!(
      account: account,
      namespace: "laravel",
      name: "docs",
      slug: "laravel",
      display_name: "Laravel"
    )
    existing = library.library_sources.create!(
      url: "https://github.com/laravel/docs/",
      source_type: "github"
    )

    match = LibrarySource.find_matching(
      url: "https://github.com/laravel/docs/tree/12.x",
      source_type: "github"
    )

    assert_equal existing.id, match.id
  end
end
