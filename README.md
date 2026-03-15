# ContextQMD Registry

Documentation package registry for [ContextQMD](https://contextqmd.com). A Rails application that crawls, indexes, and serves library documentation for MCP-based coding assistants.

## What it does

The registry is the backend for [contextqmd-mcp](https://github.com/darkamenosa/contextqmd-mcp). It:

- Crawls documentation from GitHub, GitLab, Bitbucket repos, llms.txt files, websites, and OpenAPI specs
- Splits docs into versioned pages with headings, checksums, and full-text search metadata
- Builds deterministic `tar.gz` bundles per library version for bundle-first installs
- Serves a public REST API consumed by MCP clients
- Provides a web UI for browsing libraries, submitting crawl requests, and managing accounts
- Includes a staff admin panel for library/user/proxy management

## Tech Stack

| Layer | Technology |
|-------|------------|
| **Backend** | Ruby 3.4.6, Rails 8.1, PostgreSQL 18 |
| **Frontend** | React 19, TypeScript 5.9, Inertia.js, Tailwind CSS 4, shadcn/ui, Vite 7 |
| **Background jobs** | Solid Queue (database-backed, no Redis) |
| **Caching** | Solid Cache (database-backed) |
| **WebSockets** | Solid Cable (database-backed) |
| **File storage** | Cloudflare R2 (S3-compatible) + local disk |
| **Auth** | Devise + Google OAuth2 |
| **Search** | PostgreSQL full-text search (pg_search) |
| **Deployment** | Kamal, Docker, Hetzner |
| **SSR** | Vite SSR with React hydration in production |

## Setup

```bash
bin/setup              # Install deps, create databases, run migrations, seed
bin/dev                # Start Rails + Vite dev server + Solid Queue
```

Requires PostgreSQL running locally. Default config connects to `localhost:5432`.

Rails uses 4 databases per environment: primary, cache (Solid Cache), queue (Solid Queue), and cable (Solid Cable).

### Development Data

To wipe stale local docs data and queue a fresh crawl set:

```bash
bin/rake contextqmd:dev:refresh_catalog
```

This queues a small canonical catalog (`rails/rails`, `inertia-rails`, `vite_ruby`, `react.dev`, `next.js`, `expressjs.com`) using the first staff identity. Override with:

```bash
SUBMITTER_EMAIL=you@example.com \
URLS='https://github.com/rails/rails,https://github.com/inertiajs/inertia-rails' \
bin/rake contextqmd:dev:submit_catalog
```

## Domain Model

```
Identity ──< User >── Account
    │                    │
    ├──< AccessToken     ├──< Library ──< Version ──< Page
    │                    │       │           ├──< Bundle (tar.gz archives)
    ├──< CrawlRequest ──┘       │           └── FetchRecipe
                                └── SourcePolicy

CrawlProxyConfig ──< CrawlProxyLease
```

- **Identity** — authentication entity (Devise). One identity can belong to multiple accounts (multi-tenancy).
- **Account** — tenant boundary. Has an owner user and a system user.
- **Library** — a documentation package (e.g., `react`, `rails`). Has JSON aliases for resolution and crawl rules.
- **Version** — belongs to a library (e.g., `18.2.0`, `latest`). Channels: stable, latest, canary, snapshot.
- **Page** — a single documentation page. Markdown content stored in `description` column. Full-text search indexed.
- **Bundle** — downloadable `tar.gz` archive of all pages for a version. Backed by Active Storage (R2 or local).
- **FetchRecipe** — records how a version was crawled (source type, URL, normalizer config).
- **SourcePolicy** — licensing and mirroring permissions for a library.
- **CrawlRequest** — job entry point. On creation, enqueues `ProcessCrawlRequestJob` for the full fetch-and-import pipeline.
- **CrawlProxyConfig/Lease** — proxy pool for outbound HTTP during crawling, with health tracking and lease-based concurrency.

## API

All read endpoints are public (no auth). Write endpoints use Bearer token authentication. Rate limits: 300/min default, 120/min for resolve, 60/min for query.

### Primary install flow

1. `POST /api/v1/resolve` — resolve a query to the canonical library slug + version
2. `GET /api/v1/libraries/:slug/versions/:v/manifest` — get version manifest with page checksums
3. `GET /api/v1/libraries/:slug/versions/:v/bundles/:profile` — download docs bundle

### All endpoints

| Method | Endpoint | Auth | Description |
|--------|----------|------|-------------|
| GET | `/api/v1/health` | No | Health check |
| GET | `/api/v1/capabilities` | No | Server capabilities and supported source types |
| GET | `/api/v1/libraries` | No | List/search libraries (cursor pagination) |
| GET | `/api/v1/libraries/:slug` | No | Library details with stats |
| GET | `/api/v1/libraries/:slug/versions` | No | List versions (cursor pagination, channel filter) |
| GET | `/api/v1/libraries/:slug/versions/:v/manifest` | No | Version manifest (pages, checksums, source policy) |
| GET | `/api/v1/libraries/:slug/versions/:v/bundles/:profile` | No | Binary docs bundle download |
| GET | `/api/v1/libraries/:slug/versions/:v/page-index` | No | Paginated page index |
| GET | `/api/v1/libraries/:slug/versions/:v/pages/:uid` | No | Single page content |
| POST | `/api/v1/resolve` | No | Resolve library name/alias to canonical ID |
| POST | `/api/v1/libraries/:slug/versions/:v/query` | No | Semantic doc search (debug/experimental) |
| POST | `/api/v1/crawl` | Yes | Submit a URL to crawl |

## Crawl Pipeline

Source type is auto-detected from the URL. Submit crawl requests through the web UI or the API.

| Source | Example URL | Strategy |
|--------|-------------|----------|
| **GitHub** | `https://github.com/hotwired/stimulus` | Clone + discover doc files (.md, .mdx, .rst, .ipynb) |
| **GitLab** | `https://gitlab.com/org/repo` | Repository API v4 |
| **Bitbucket** | `https://bitbucket.org/org/repo` | Git clone |
| **llms.txt** | `https://react.dev/llms.txt` | Tries llms-full.txt first, falls back to index-follow or heading-split |
| **Website** | `https://stimulus.hotwired.dev/` | BFS HTML crawl (Ruby) with Playwright fallback for JS-rendered sites |
| **OpenAPI** | `https://petstore3.swagger.io/api/v3/openapi.json` | Parse spec into endpoint + schema pages |

The pipeline supports configurable crawl rules per library (include/exclude paths), a proxy pool with health tracking and exponential backoff, and SSRF protection for all outbound requests.

## Web UI

The frontend is a React 19 + Inertia.js SPA with three layout zones:

### Public pages
- **Home** — hero search, tabbed library table (popular/trending/recent), feature cards
- **Libraries** — browse/search with card grid, library detail with pages/versions/usage tabs
- **Rankings** — libraries ranked by documentation coverage
- **Queue** — live crawl request status (active/completed tabs)
- **Doc pages** — full page view with TOC sidebar and markdown rendering

### App pages (authenticated, account-scoped at `/app/:account_id/`)
- **Dashboard** — account stats, recent crawls and libraries
- **Submit docs** — crawl request form with source type selector
- **Access tokens** — create/revoke API tokens
- **Settings** — profile, password, account cancellation

### Admin pages (staff-only at `/admin/`)
- **Dashboard** — system-wide stats and recent crawl activity
- **Libraries** — CRUD, version management, re-crawl, crawl rules editor
- **Users** — identity management, suspend/unsuspend, staff access, bulk actions
- **Proxy pool** — CRUD for crawl proxy configs with health/capacity monitoring
- **Jobs** — Mission Control dashboard for Solid Queue

## Background Jobs

| Job | Queue | Purpose |
|-----|-------|---------|
| `ProcessCrawlRequestJob` | `default` or `crawl_website` | Full crawl lifecycle: fetch docs, import pages, build bundle |
| `BuildBundleJob` | `default` | Build/rebuild a documentation bundle |
| `AccountIncinerationJob` | `background` | Destroy cancelled accounts past 30-day grace period |

Queue config: `default` (3 threads), `crawl_website` (1 thread, isolated for slow BFS crawls). Recurring: hourly Solid Queue cleanup, daily account incineration at 3am.

## Tests

```bash
bin/rails test             # All tests
bin/rubocop                # Ruby linting
npm run check              # TypeScript type check
npm run lint               # ESLint
npm run format:check       # Prettier
bin/ci                     # Full CI pipeline (all of the above + security scans + asset build)
```

CI runs on GitHub Actions with 3 parallel jobs: security scan (Brakeman + bundler-audit), lint (RuboCop + TS + ESLint + Prettier), and test (PostgreSQL service container).

## Project Structure

```
app/
  controllers/
    api/v1/              # Public REST API (ActionController::API)
    app/                 # Authenticated web app (account-scoped)
    admin/               # Staff-only admin panel
    concerns/            # Auth, authorization, error handling, CSRF, tenanting
    identities/          # Devise session/registration/password/OAuth controllers
  models/
    account/             # Cancellable, Incineratable concerns
    user/                # Named, Role concerns
    docs_fetcher/        # Crawl pipeline (Git, LlmsTxt, Website, Openapi)
    docs_fetcher/git/    # GitHub, GitLab, Bitbucket fetchers
    docs_fetcher/website/ # RubyRunner (BFS), NodeRunner (Playwright)
  jobs/                  # ProcessCrawlRequestJob, BuildBundleJob, AccountIncinerationJob
  frontend/
    pages/               # 41 Inertia React pages (public, app, admin, auth, errors)
    components/          # Shared, admin, app components + shadcn/ui primitives
    layouts/             # PersistentLayout, PublicLayout, AdminLayout, AppLayout
    lib/                 # Utilities (inertia resolver, account scoping, date formatting)
    types/               # TypeScript type definitions
    entrypoints/         # Vite entry points (client + SSR)
config/
  deploy.yml             # Kamal deployment (3 containers: web, vite SSR, jobs)
  storage.yml            # Local disk + Cloudflare R2 (public/private)
  queue.yml              # Solid Queue worker pools
  recurring.yml          # Recurring jobs (cleanup, incineration)
test/
  models/                # 16+ model test files including all fetcher types
  controllers/api/v1/    # API endpoint tests
  integration/           # Auth, tenanting, scoping integration tests
  jobs/                  # Job tests
  fixtures/              # YAML fixture data
```

## Deployment

Deployed via Kamal to a single Hetzner server running 3 Docker containers:

- **web** — Rails + Thruster/Puma (port 80, Let's Encrypt SSL)
- **vite** — SSR server (`node public/vite-ssr/ssr.js`)
- **job** — Solid Queue worker

PostgreSQL 18 runs as a Kamal accessory on the same host. Active Storage files persist via a Docker volume, with Cloudflare R2 for production bundle storage.

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `POSTGRES_PASSWORD` | production | Database password |
| `RAILS_MASTER_KEY` | production | Decrypts credentials |
| `DB_HOST` | production | PostgreSQL host |
| `APP_HOST` | production | Application hostname (default: `contextqmd.com`) |
| `CRAWL_PROXY_URLS` | no | Comma-separated proxy URLs for crawl HTTP requests |
| `WEB_CONCURRENCY` | no | Puma worker count |
| `RAILS_MAX_THREADS` | no | Puma threads per worker (default: 3) |
| `JOB_CONCURRENCY` | no | Solid Queue process count |
| `SOLID_QUEUE_IN_PUMA` | no | Run Solid Queue inside Puma process |

## License

MIT
