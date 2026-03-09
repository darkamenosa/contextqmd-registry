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
    bytes: 9123, checksum: "sha256:install_page_hash",
    description: <<~MD
      # Installation

      ## Automatic installation

      We recommend starting a new Next.js app using `create-next-app`, which sets up everything automatically for you.

      ```bash
      npx create-next-app@latest
      ```

      On installation, you'll see prompts for project name, TypeScript, ESLint, Tailwind CSS, `src/` directory, App Router, and import alias.

      ## Manual installation

      To manually create a new Next.js app, install the required packages:

      ```bash
      npm install next@latest react@latest react-dom@latest
      ```

      Add the following scripts to your `package.json`:

      ```json
      {
        "scripts": {
          "dev": "next dev",
          "build": "next build",
          "start": "next start",
          "lint": "next lint"
        }
      }
      ```
    MD
  },
  { page_uid: "pg_nextjs_routing", path: "app/building-your-application/routing.md",
    title: "Routing", url: "https://nextjs.org/docs/app/building-your-application/routing",
    headings: ["Routing", "Defining routes", "Pages", "Layouts"],
    bytes: 15420, checksum: "sha256:routing_page_hash",
    description: <<~MD
      # Routing

      Next.js uses a file-system based router where folders are used to define routes.

      ## Defining routes

      Each folder in the `app` directory represents a route segment. Nested folders create nested routes. A `page.js` file makes a route segment publicly accessible.

      ```
      app/
        page.js          -> /
        about/
          page.js        -> /about
        blog/
          [slug]/
            page.js      -> /blog/:slug
      ```

      ## Pages

      A page is UI that is unique to a route. You define a page by exporting a component from a `page.js` file.

      ```tsx
      export default function Page() {
        return <h1>Hello, Next.js!</h1>
      }
      ```

      ## Layouts

      A layout is UI that is shared between multiple routes. Layouts preserve state, remain interactive, and do not re-render on navigation.

      ```tsx
      export default function RootLayout({ children }) {
        return (
          <html lang="en">
            <body>{children}</body>
          </html>
        )
      }
      ```
    MD
  },
  { page_uid: "pg_nextjs_data_fetching", path: "app/building-your-application/data-fetching.md",
    title: "Data Fetching", url: "https://nextjs.org/docs/app/building-your-application/data-fetching",
    headings: ["Data Fetching", "fetch API", "Server Components"],
    bytes: 12800, checksum: "sha256:data_fetching_page_hash",
    description: <<~MD
      # Data Fetching

      Next.js extends the native `fetch` Web API to allow you to configure the caching and revalidating behavior for each fetch request on the server.

      ## fetch API

      You can use `fetch` with `async`/`await` in Server Components, in Route Handlers, and in Server Actions.

      ```tsx
      async function getData() {
        const res = await fetch('https://api.example.com/...')
        if (!res.ok) throw new Error('Failed to fetch data')
        return res.json()
      }

      export default async function Page() {
        const data = await getData()
        return <main>{JSON.stringify(data)}</main>
      }
      ```

      ## Server Components

      Server Components allow you to fetch data directly in the component without useEffect or useState. This reduces the amount of JavaScript sent to the client.
    MD
  },
  { page_uid: "pg_nextjs_rendering", path: "app/building-your-application/rendering.md",
    title: "Rendering", url: "https://nextjs.org/docs/app/building-your-application/rendering",
    headings: ["Rendering", "Server Components", "Client Components"],
    bytes: 18200, checksum: "sha256:rendering_page_hash",
    description: <<~MD
      # Rendering

      Rendering converts the code you write into user interfaces. React and Next.js allow you to create hybrid web applications where parts of your code can be rendered on the server or the client.

      ## Server Components

      React Server Components allow you to write UI that can be rendered and optionally cached on the server. By default, Next.js uses Server Components.

      Benefits of server rendering:
      - **Data Fetching**: Fetch data closer to your data source
      - **Security**: Keep sensitive data on the server
      - **Performance**: Reduce client-side JavaScript bundle
      - **SEO**: Server-rendered HTML is crawlable

      ## Client Components

      Client Components allow you to write interactive UI that is prerendered on the server and uses client JavaScript to run in the browser.

      Use the `"use client"` directive at the top of a file to define a Client Component:

      ```tsx
      'use client'

      import { useState } from 'react'

      export default function Counter() {
        const [count, setCount] = useState(0)
        return <button onClick={() => setCount(count + 1)}>Count: {count}</button>
      }
      ```
    MD
  },
  { page_uid: "pg_nextjs_caching", path: "app/building-your-application/caching.md",
    title: "Caching", url: "https://nextjs.org/docs/app/building-your-application/caching",
    headings: ["Caching", "Request Memoization", "Data Cache", "Full Route Cache"],
    bytes: 22100, checksum: "sha256:caching_page_hash",
    description: <<~MD
      # Caching

      Next.js improves your application's performance and reduces costs by caching rendering work and data requests.

      ## Request Memoization

      React extends the `fetch` API to automatically memoize requests with the same URL and options. You can call fetch for the same data in multiple places in a React component tree while only executing it once.

      ## Data Cache

      Next.js has a built-in Data Cache that persists the result of data fetches across incoming server requests and deployments. `fetch` requests that use `force-cache` or `no-store` opt into the Data Cache.

      ```tsx
      // Cached by default
      fetch('https://...', { cache: 'force-cache' })

      // Not cached
      fetch('https://...', { cache: 'no-store' })
      ```

      ## Full Route Cache

      Next.js automatically renders and caches routes at build time. The Full Route Cache allows you to serve the cached result instead of rendering on every request.
    MD
  }
]

nextjs_pages.each do |attrs|
  Page.find_or_create_by!(version: nextjs_stable, page_uid: attrs[:page_uid]) do |p|
    p.path = attrs[:path]
    p.title = attrs[:title]
    p.url = attrs[:url]
    p.headings = attrs[:headings]
    p.bytes = attrs[:bytes]
    p.checksum = attrs[:checksum]
    p.description = attrs[:description]
  end
end

# --- Sample Pages (Rails stable) ---
rails_pages = [
  { page_uid: "pg_rails_getting_started", path: "getting-started.md",
    title: "Getting Started with Rails", url: "https://guides.rubyonrails.org/getting_started.html",
    headings: ["Getting Started", "Creating a New Rails Project", "MVC Architecture"],
    bytes: 25000, checksum: "sha256:rails_getting_started",
    description: <<~MD
      # Getting Started with Rails

      This guide covers getting up and running with Ruby on Rails.

      ## Creating a New Rails Project

      ```bash
      rails new myapp --database=postgresql
      cd myapp
      bin/rails server
      ```

      ## MVC Architecture

      Rails follows the Model-View-Controller architectural pattern:
      - **Models** handle data and business logic
      - **Views** handle the display of information
      - **Controllers** handle the flow between models and views
    MD
  },
  { page_uid: "pg_rails_active_record", path: "active-record-basics.md",
    title: "Active Record Basics", url: "https://guides.rubyonrails.org/active_record_basics.html",
    headings: ["Active Record", "CRUD Operations", "Validations", "Migrations"],
    bytes: 32000, checksum: "sha256:rails_active_record",
    description: <<~MD
      # Active Record Basics

      Active Record is the M in MVC - the model. It facilitates creation and use of business objects whose data requires persistent storage to a database.

      ## CRUD Operations

      Active Record provides methods for creating, reading, updating, and deleting data:

      ```ruby
      # Create
      user = User.create(name: "David", email: "david@example.com")

      # Read
      users = User.all
      user = User.find(1)

      # Update
      user.update(name: "Dave")

      # Delete
      user.destroy
      ```

      ## Validations

      ```ruby
      class User < ApplicationRecord
        validates :name, presence: true
        validates :email, uniqueness: true
      end
      ```

      ## Migrations

      ```ruby
      class CreateUsers < ActiveRecord::Migration[8.0]
        def change
          create_table :users do |t|
            t.string :name
            t.string :email
            t.timestamps
          end
        end
      end
      ```
    MD
  }
]

rails_pages.each do |attrs|
  Page.find_or_create_by!(version: rails_stable, page_uid: attrs[:page_uid]) do |p|
    p.path = attrs[:path]
    p.title = attrs[:title]
    p.url = attrs[:url]
    p.headings = attrs[:headings]
    p.bytes = attrs[:bytes]
    p.checksum = attrs[:checksum]
    p.description = attrs[:description]
  end
end

# --- Sample Pages (React stable) ---
react_pages = [
  { page_uid: "pg_react_hooks", path: "reference/react/hooks.md",
    title: "React Hooks", url: "https://react.dev/reference/react/hooks",
    headings: ["Hooks", "useState", "useEffect", "useContext"],
    bytes: 18000, checksum: "sha256:react_hooks",
    description: <<~MD
      # React Hooks

      Hooks let you use state and other React features in function components.

      ## useState

      `useState` declares a state variable that you can update directly.

      ```tsx
      const [count, setCount] = useState(0)
      ```

      ## useEffect

      `useEffect` connects a component to an external system.

      ```tsx
      useEffect(() => {
        const connection = createConnection(serverUrl, roomId)
        connection.connect()
        return () => connection.disconnect()
      }, [serverUrl, roomId])
      ```

      ## useContext

      `useContext` reads and subscribes to a context from your component.

      ```tsx
      const theme = useContext(ThemeContext)
      ```
    MD
  }
]

react_pages.each do |attrs|
  Page.find_or_create_by!(version: react_stable, page_uid: attrs[:page_uid]) do |p|
    p.path = attrs[:path]
    p.title = attrs[:title]
    p.url = attrs[:url]
    p.headings = attrs[:headings]
    p.bytes = attrs[:bytes]
    p.checksum = attrs[:checksum]
    p.description = attrs[:description]
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
