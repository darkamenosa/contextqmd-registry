# frozen_string_literal: true

require "test_helper"

class PublicDefaultMembershipTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "public crawl entrypoint redirects to the default membership account" do
    identity = Identity.create!(
      email: "public-crawl-default-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )

    member_account = Account.create!(name: "Member Account", personal: false)
    member_account.users.create!(name: "System", role: :system)
    member_account.users.create!(identity: identity, name: "Public User", role: :member)

    admin_account = Account.create!(name: "Admin Account", personal: false)
    admin_account.users.create!(name: "System", role: :system)
    admin_account.users.create!(identity: identity, name: "Public User", role: :admin)

    sign_in(identity)

    get new_crawl_request_path

    assert_redirected_to new_app_crawl_request_path(account_id: admin_account.external_account_id)
  ensure
    Current.reset
  end

  test "public library submission uses the default membership account" do
    identity = Identity.create!(
      email: "public-library-default-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )

    member_account = Account.create!(name: "Member Account", personal: false)
    member_account.users.create!(name: "System", role: :system)
    member_account.users.create!(identity: identity, name: "Public User", role: :member)

    admin_account = Account.create!(name: "Admin Account", personal: false)
    admin_account.users.create!(name: "System", role: :system)
    admin_account.users.create!(identity: identity, name: "Public User", role: :admin)

    sign_in(identity)

    namespace = "public-lib-#{SecureRandom.hex(4)}"

    post libraries_path, params: {
      library: {
        namespace: namespace,
        name: "docs",
        display_name: "Public Docs",
        homepage_url: "https://example.com/docs",
        default_version: "1.0.0",
        aliases: [ "public-docs" ]
      }
    }

    library = Library.find_by!(namespace: namespace, name: "docs")
    assert_equal admin_account.id, library.account_id
    assert_redirected_to detail_libraries_path(namespace: library.namespace, name: library.name)
  ensure
    Current.reset
  end
end
