# frozen_string_literal: true

require "test_helper"
require "json"

class App::MenusDefaultAccountTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "current identity default account prefers higher role over lexical role order" do
    identity = Identity.create!(
      email: "menus-default-account-#{SecureRandom.hex(4)}@example.com",
      password: "password123",
      password_confirmation: "password123"
    )

    admin_account = Account.create!(name: "Admin Account", personal: false)
    admin_account.users.create!(name: "System", role: :system)
    admin_account.users.create!(identity: identity, name: "Menus User", role: :admin)

    member_account = Account.create!(name: "Member Account", personal: false)
    member_account.users.create!(name: "System", role: :system)
    member_account.users.create!(identity: identity, name: "Menus User", role: :member)

    sign_in(identity)

    get app_path

    assert_response :success
    assert_equal(
      admin_account.external_account_id,
      page_props.dig("props", "currentIdentity", "defaultAccountId")
    )
  ensure
    Current.reset
  end

  private
    def page_props
      page_node = Nokogiri::HTML5(response.body).at_css("script[data-page]")
      JSON.parse(page_node.text)
    end
end
