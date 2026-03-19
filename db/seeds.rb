# frozen_string_literal: true

# Minimal seed data for development.
# To populate libraries with real content, use the crawl pipeline:
#   POST /api/v1/crawl with { url: "https://github.com/rails/rails" }
#
# Usage: bin/rails db:seed

puts "Seeding ContextQMD development data..."

# System account — owns registry-managed libraries and acts as the system actor.
system_account = Account.find_or_create_by!(name: Account::SYSTEM_ACCOUNT_NAME) { |a| a.personal = false }
system_account.users.find_or_create_by!(role: :system) { |u| u.name = "System" }

puts "Done."
