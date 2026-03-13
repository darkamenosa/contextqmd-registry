# ContextQMD Registry

Documentation package registry for ContextQMD. A Rails API that stores, indexes, and serves library documentation for MCP-based coding assistants.

## What it does

The registry is the backend for [contextqmd-mcp](https://github.com/darkamenosa/contextqmd-mcp). It:

- Crawls documentation from GitHub repos, llms.txt files, websites, and OpenAPI specs
- Splits docs into versioned pages with headings, checksums, and search metadata
- Builds deterministic `tar.gz` bundles per library version for bundle-first installs
- Serves a public REST API consumed by MCP clients
- Provides a web UI for browsing libraries, submitting crawl requests, and managing accounts

## Tech Stack

- **Ruby 3.4** / **Rails 8.1** / **PostgreSQL**
- **Inertia.js** + **React** + **TypeScript** + **Tailwind CSS 4** (frontend)
- **Solid Queue** / **Solid Cache** / **Solid Cable** (background jobs, caching, WebSockets)
- **Vite** with SSR support
- **Kamal** for deployment

## Setup

```bash
bin/setup              # Install deps, create databases, run migrations, seed
bin/dev                # Start Rails + Vite + Solid Queue
```

Requires PostgreSQL running locally. Default config connects to `localhost:5432`.

To wipe stale local docs data and queue a fresh crawl set for development:

```bash
bin/rake contextqmd:dev:refresh_catalog
```

By default that queues a small canonical catalog (`rails/rails`, `inertia-rails`, `vite_ruby`, `react.dev`, `next.js`, `expressjs.com`) using the first staff identity or first identity in the local DB. You can override both:

```bash
SUBMITTER_EMAIL=you@example.com \
URLS='https://github.com/rails/rails,https://github.com/inertiajs/inertia-rails' \
bin/rake contextqmd:dev:submit_catalog
```

## API

All read endpoints are public (no auth required). Write endpoints use HTTP Token authentication.

The primary install flow is:

1. `POST /api/v1/resolve`
2. `GET /api/v1/libraries/:ns/:name/versions/:v/manifest`
3. `GET /api/v1/libraries/:ns/:name/versions/:v/bundles/:profile`

Bundles are generated locally and stored on disk under `tmp/contextqmd/bundles/...` for now. The binary bundle endpoint streams those archives directly from Rails. Page-by-page content endpoints remain available as metadata/fallback paths.

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/v1/health` | Health check |
| GET | `/api/v1/capabilities` | Server capabilities |
| GET | `/api/v1/libraries` | List/search libraries |
| GET | `/api/v1/libraries/:ns/:name` | Library details |
| GET | `/api/v1/libraries/:ns/:name/versions` | List versions |
| GET | `/api/v1/libraries/:ns/:name/versions/:v/manifest` | Version manifest (pages + checksums) |
| GET | `/api/v1/libraries/:ns/:name/versions/:v/bundles/:profile` | Binary docs bundle download |
| GET | `/api/v1/libraries/:ns/:name/versions/:v/page-index` | Paginated page index |
| GET | `/api/v1/libraries/:ns/:name/versions/:v/pages/:uid` | Single page content |
| POST | `/api/v1/resolve` | Resolve library name/alias to canonical ID |
| POST | `/api/v1/crawl` | Submit a URL to crawl (token required) |

Remote `POST /api/v1/libraries/:ns/:name/versions/:v/query` still exists for debugging and experimentation, but it is not part of the primary MCP install/search flow. MCP installs packages locally and searches with QMD on the client side.

## Crawl Pipeline

The registry can ingest documentation from multiple source types:

| Source | Example URL | Strategy |
|--------|-------------|----------|
| **GitHub** | `https://github.com/hotwired/stimulus` | Tree API, fetch markdown files |
| **llms.txt** | `https://react.dev/llms.txt` | Tries llms-full.txt first, falls back to index-follow or heading-split |
| **Website** | `https://stimulus.hotwired.dev/` | BFS HTML crawl with HTML-to-Markdown conversion |
| **OpenAPI** | `https://petstore3.swagger.io/api/v3/openapi.json` | Parse spec into endpoint pages |
| **GitLab** | `https://gitlab.com/org/repo` | Repository API v4 |

Source type is auto-detected from the URL. Submit crawl requests through the web UI or the API.

## Tests

```bash
bin/rails test             # 341 tests, 980 assertions
bin/rubocop                # 175 files, 0 offenses
npm run check              # TypeScript type check
npm run lint               # ESLint
```

## Project Structure

```
app/
  controllers/
    api/v1/         # Public REST API
    app/            # Authenticated web app
    admin/          # Staff-only admin
  models/
    docs_fetcher/   # Crawl pipeline (GitHub, LlmsTxt, Website, OpenAPI, GitLab)
  jobs/             # ProcessCrawlRequestJob
  frontend/
    pages/          # Inertia React pages
    components/     # React components
```

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `POSTGRES_PASSWORD` | production | Database password |
| `RAILS_MASTER_KEY` | production | Decrypts credentials |
| `CRAWL_PROXY_URLS` | no | Comma-separated proxy URLs for crawl HTTP requests |

## License

MIT
