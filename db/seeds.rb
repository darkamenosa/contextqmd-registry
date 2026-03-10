# frozen_string_literal: true

# Minimal seed data for development.
# To populate libraries with real content, use the crawl pipeline:
#   POST /api/v1/crawl with { url: "https://github.com/rails/rails" }
#
# Usage: bin/rails db:seed

puts "Seeding ContextQMD development data..."

# System account used by the import pipeline for registry-owned libraries.
Account.find_or_create_by!(name: "ContextQMD System") { |a| a.personal = false }

puts "Done."
