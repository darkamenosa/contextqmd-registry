# frozen_string_literal: true

require "test_helper"

class Admin::LibraryMetadataLockingTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "admin updates lock library metadata for future recrawls" do
    staff_identity, = create_tenant(
      email: "staff-library-lock-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Admin"
    )
    staff_identity.update!(staff: true)

    _owner_identity, account, = create_tenant(
      email: "library-owner-#{SecureRandom.hex(4)}@example.com",
      name: "Library Owner"
    )
    library = Library.create!(
      account: account,
      namespace: "laravel",
      name: "docs",
      display_name: "Docs",
      homepage_url: "https://github.com/laravel/docs",
      aliases: [ "docs" ]
    )

    sign_in(staff_identity)

    patch admin_library_path(id: library.id), params: {
      library: {
        display_name: "Laravel",
        homepage_url: "https://laravel.com/docs",
        default_version: nil,
        aliases: [ "laravel", "docs" ]
      }
    }

    assert_redirected_to admin_library_path(id: library.id)
    assert_predicate library.reload, :metadata_locked?
    assert_equal "Laravel", library.display_name
    assert_equal "https://laravel.com/docs", library.homepage_url
  ensure
    Current.reset
  end

  test "admin can update canonical slug" do
    staff_identity, = create_tenant(
      email: "staff-library-slug-#{SecureRandom.hex(4)}@example.com",
      name: "Staff Admin"
    )
    staff_identity.update!(staff: true)

    _owner_identity, account, = create_tenant(
      email: "library-slug-owner-#{SecureRandom.hex(4)}@example.com",
      name: "Library Owner"
    )
    library = Library.create!(
      account: account,
      namespace: "laravel",
      name: "docs",
      slug: "docs",
      display_name: "Laravel Docs",
      homepage_url: "https://github.com/laravel/docs",
      aliases: [ "docs" ]
    )

    sign_in(staff_identity)

    patch admin_library_path(id: library.id), params: {
      library: {
        slug: "laravel",
        display_name: "Laravel",
        homepage_url: "https://laravel.com/docs",
        default_version: nil,
        aliases: [ "laravel", "docs" ]
      }
    }

    assert_redirected_to admin_library_path(id: library.id)
    assert_equal "laravel", library.reload.slug
    assert_predicate library, :metadata_locked?
  ensure
    Current.reset
  end
end
