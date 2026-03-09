# frozen_string_literal: true

# Seed data for ContextQMD Registry benchmark scenarios.
# Idempotent: safe to run multiple times.
#
# Usage: bin/rails db:seed

puts "Seeding ContextQMD benchmark data..."

# --- System account for registry-owned libraries ---
system_account = Account.find_or_create_by!(name: "ContextQMD System") do |a|
  a.personal = false
end

# --- Libraries ---
nextjs = Library.find_or_create_by!(namespace: "vercel", name: "nextjs") do |lib|
  lib.account = system_account
  lib.display_name = "Next.js"
  lib.aliases = %w[next nextjs next.js]
  lib.homepage_url = "https://nextjs.org"
  lib.default_version = "16.1.6"
end

rails = Library.find_or_create_by!(namespace: "rails", name: "rails") do |lib|
  lib.account = system_account
  lib.display_name = "Ruby on Rails"
  lib.aliases = %w[rails rubyonrails ror]
  lib.homepage_url = "https://rubyonrails.org"
  lib.default_version = "8.1.0"
end

inertia = Library.find_or_create_by!(namespace: "inertiajs", name: "inertia") do |lib|
  lib.account = system_account
  lib.display_name = "Inertia.js"
  lib.aliases = %w[inertia inertiajs]
  lib.homepage_url = "https://inertiajs.com"
  lib.default_version = "2.0.0"
end

react = Library.find_or_create_by!(namespace: "facebook", name: "react") do |lib|
  lib.account = system_account
  lib.display_name = "React"
  lib.aliases = %w[react reactjs]
  lib.homepage_url = "https://react.dev"
  lib.default_version = "19.1.0"
end

tailwind = Library.find_or_create_by!(namespace: "tailwindlabs", name: "tailwindcss") do |lib|
  lib.account = system_account
  lib.display_name = "Tailwind CSS"
  lib.aliases = %w[tailwind tailwindcss]
  lib.homepage_url = "https://tailwindcss.com"
  lib.default_version = "4.1.0"
end

puts "  #{Library.count} libraries"

# --- Versions ---
def find_or_create_version(library, attrs)
  Version.find_or_create_by!(library: library, version: attrs[:version]) do |v|
    v.channel = attrs[:channel]
    v.generated_at = attrs[:generated_at]
    v.source_url = attrs[:source_url]
    v.manifest_checksum = attrs[:manifest_checksum]
  end
end

nextjs_stable = find_or_create_version(nextjs,
  version: "16.1.6", channel: "stable",
  generated_at: 2.days.ago,
  source_url: "https://nextjs.org/docs/llms-full.txt",
  manifest_checksum: "sha256:nextjs1616stable")

nextjs_canary = find_or_create_version(nextjs,
  version: "17.0.0-canary.1", channel: "canary",
  generated_at: 1.day.ago,
  source_url: "https://nextjs.org/docs/llms-full.txt",
  manifest_checksum: nil)

rails_stable = find_or_create_version(rails,
  version: "8.1.0", channel: "stable",
  generated_at: 3.days.ago,
  source_url: "https://guides.rubyonrails.org",
  manifest_checksum: "sha256:rails810stable")

inertia_stable = find_or_create_version(inertia,
  version: "2.0.0", channel: "stable",
  generated_at: 5.days.ago,
  source_url: "https://inertiajs.com/",
  manifest_checksum: "sha256:inertia200stable")

react_stable = find_or_create_version(react,
  version: "19.1.0", channel: "stable",
  generated_at: 4.days.ago,
  source_url: "https://react.dev/llms-full.txt",
  manifest_checksum: "sha256:react1910stable")

tailwind_stable = find_or_create_version(tailwind,
  version: "4.1.0", channel: "stable",
  generated_at: 6.days.ago,
  source_url: "https://tailwindcss.com/docs",
  manifest_checksum: "sha256:tailwind410stable")

puts "  #{Version.count} versions"

# --- Source Policies ---
[nextjs, rails, inertia, react, tailwind].each do |lib|
  SourcePolicy.find_or_create_by!(library: lib) do |sp|
    sp.license_name = "MIT"
    sp.license_status = "verified"
    sp.mirror_allowed = true
    sp.origin_fetch_allowed = true
    sp.attribution_required = false
  end
end

puts "  #{SourcePolicy.count} source policies"

# --- Fetch Recipes (one per version) ---
{
  nextjs_stable => { source_type: "llms_full_txt", url: "https://nextjs.org/docs/llms-full.txt" },
  rails_stable => { source_type: "github_markdown", url: "https://github.com/rails/rails/tree/v8.1.0/guides/source" },
  inertia_stable => { source_type: "github_markdown", url: "https://github.com/inertiajs/inertia/tree/v2.0/docs" },
  react_stable => { source_type: "llms_full_txt", url: "https://react.dev/llms-full.txt" },
  tailwind_stable => { source_type: "github_markdown", url: "https://github.com/tailwindlabs/tailwindcss.com/tree/main/src/docs" }
}.each do |version, attrs|
  FetchRecipe.find_or_create_by!(version: version) do |fr|
    fr.source_type = attrs[:source_type]
    fr.url = attrs[:url]
    fr.normalizer_version = "2026-03-01"
    fr.splitter_version = "frontmatter-blocks-v2"
  end
end

puts "  #{FetchRecipe.count} fetch recipes"

# --- Sample Pages (Next.js stable — enough for benchmark B30) ---
nextjs_pages = [
  { page_uid: "pg_nextjs_installation", path: "app/getting-started/installation.md",
    title: "Installation", url: "https://nextjs.org/docs/app/getting-started/installation",
    headings: ["Installation", "Automatic installation", "Manual installation"],
    bytes: 9123, checksum: "sha256:install_page_hash" },
  { page_uid: "pg_nextjs_routing", path: "app/building-your-application/routing.md",
    title: "Routing", url: "https://nextjs.org/docs/app/building-your-application/routing",
    headings: ["Routing", "Defining routes", "Pages", "Layouts"],
    bytes: 15420, checksum: "sha256:routing_page_hash" },
  { page_uid: "pg_nextjs_data_fetching", path: "app/building-your-application/data-fetching.md",
    title: "Data Fetching", url: "https://nextjs.org/docs/app/building-your-application/data-fetching",
    headings: ["Data Fetching", "fetch API", "Server Components"],
    bytes: 12800, checksum: "sha256:data_fetching_page_hash" },
  { page_uid: "pg_nextjs_rendering", path: "app/building-your-application/rendering.md",
    title: "Rendering", url: "https://nextjs.org/docs/app/building-your-application/rendering",
    headings: ["Rendering", "Server Components", "Client Components"],
    bytes: 18200, checksum: "sha256:rendering_page_hash" },
  { page_uid: "pg_nextjs_caching", path: "app/building-your-application/caching.md",
    title: "Caching", url: "https://nextjs.org/docs/app/building-your-application/caching",
    headings: ["Caching", "Request Memoization", "Data Cache", "Full Route Cache"],
    bytes: 22100, checksum: "sha256:caching_page_hash" }
]

nextjs_pages.each do |attrs|
  Page.find_or_create_by!(version: nextjs_stable, page_uid: attrs[:page_uid]) do |p|
    p.path = attrs[:path]
    p.title = attrs[:title]
    p.url = attrs[:url]
    p.headings = attrs[:headings]
    p.bytes = attrs[:bytes]
    p.checksum = attrs[:checksum]
  end
end

puts "  #{Page.count} pages"

# --- Bundles ---
{
  nextjs_stable => [
    { profile: "slim", format: "tar.zst", sha256: "sha256:nextjs_slim_v1616", size_bytes: 1_048_576 },
    { profile: "full", format: "tar.zst", sha256: "sha256:nextjs_full_v1616", size_bytes: 5_242_880 }
  ],
  rails_stable => [
    { profile: "slim", format: "tar.zst", sha256: "sha256:rails_slim_v810", size_bytes: 2_097_152 },
    { profile: "full", format: "tar.zst", sha256: "sha256:rails_full_v810", size_bytes: 8_388_608 }
  ]
}.each do |version, bundles|
  bundles.each do |attrs|
    Bundle.find_or_create_by!(version: version, profile: attrs[:profile]) do |b|
      b.format = attrs[:format]
      b.sha256 = attrs[:sha256]
      b.size_bytes = attrs[:size_bytes]
    end
  end
end

puts "  #{Bundle.count} bundles"
puts "Done! Seeded #{Library.count} libraries for benchmark scenarios."
