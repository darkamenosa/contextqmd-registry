# Analytics Architecture Guide

This document describes the self-hosted analytics system in this repo. It covers the data model, request pipeline, client-side tracker, live view, and the conventions needed to extend it safely.

## Overview

A Plausible-style analytics dashboard built on Ahoy. Cookieless by default. Runs in a dedicated PostgreSQL database isolated from primary app data. The admin dashboard at `/admin/analytics/reports` shows traffic stats; `/admin/analytics/live` shows real-time visitors on a 3D globe.

```text
Browser → analytics.ts tracker → /ahoy/visits + /ahoy/events
                                        ↓
                              Ahoy::Store (ahoy.rb initializer)
                                        ↓
                              analytics database (ahoy_visits, ahoy_events)
                                        ↓
                    Ahoy::Visit concern pipeline (filters, ranges, metrics, …)
                                        ↓
                    Admin::Analytics::*Controller → JSON API → React dashboard
```

## Database Isolation

All analytics tables live in a separate PostgreSQL database (`*_analytics`). Models that touch this database inherit from `AnalyticsRecord`, not `ApplicationRecord`.

```ruby
class AnalyticsRecord < ActiveRecord::Base
  self.abstract_class = true
  connects_to database: { writing: :analytics, reading: :analytics }
end
```

**Tables**: `ahoy_visits`, `ahoy_events`, `analytics_funnels`, `analytics_settings`

**Migrations** live in `db/analytics_migrate/`, not `db/migrate/`.

### When adding analytics models

- Inherit from `AnalyticsRecord`
- Put migrations in `db/analytics_migrate/`
- Never join analytics tables with primary database tables (cross-database joins are not supported)
- The `user_id` column on visits/events references `Identity#id` from the primary database but is not a foreign key constraint — it is a denormalized reference

## Data Model

### ahoy_visits

One row per visitor session. Contains all dimensions used for analytics breakdowns:

| Column group | Columns | Purpose |
|---|---|---|
| Identity | `visit_token`, `visitor_token`, `user_id` | Session + visitor tracking |
| Source | `referrer`, `referring_domain`, `utm_source/medium/campaign/content/term` | Traffic source attribution |
| Technology | `browser`, `browser_version`, `os`, `device_type`, `screen_size` | Device breakdowns |
| Location | `country`, `region`, `city`, `latitude`, `longitude` | Geo breakdowns + globe dots |
| Page | `landing_page`, `hostname` | Entry page tracking |
| Meta | `started_at`, `ip`, `user_agent`, `platform`, `app_version`, `os_version` | Timestamps and raw data |

### ahoy_events

One row per tracked action (pageview, engagement, outbound link click, file download, custom goals).

| Column | Purpose |
|---|---|
| `visit_id` | Links to the parent visit |
| `name` | Event type: `pageview`, `engagement`, `Outbound Link: Click`, `File Download`, or custom |
| `properties` | JSONB — always includes `page`, `url`, `title`, `referrer`, `screen_size`; engagement adds `engaged_ms`, `scroll_depth` |
| `time` | When the event occurred |

### analytics_funnels

Named conversion funnels with ordered step definitions (JSONB array).

### analytics_settings

Key-value store for runtime analytics configuration (e.g., `gsc_configured`).

## Client-Side Tracker

`app/frontend/entrypoints/analytics.ts` — a standalone, framework-agnostic tracker injected into the application layout via `<%= vite_typescript_tag "analytics.ts" %>`.

### How it works

1. **Server-first initial pageview**: On eligible public HTML `GET` requests, Rails creates the visit and first `pageview` before the response is sent. The layout bootstraps only the initial `pageKey` and whether the current render was already counted.
2. **Client follow-up tracking**: The standalone tracker seeds its dedupe/engagement state from that bootstrap and continues tracking SPA navigation, engagement, downloads, and outbound clicks.
3. **Event-only follow-up ingestion**: Subsequent tracking uses POST `/ahoy/events` only. Ahoy creates a new visit lazily on the next `pageview` when no recent visit exists.
4. **Engagement does not open a new visit**: `engagement` events extend an active visit, but are dropped when no recent visit exists. This matches Plausible-style session handling.
5. **Engagement tracking**: Tracks time-on-page and scroll depth (Plausible-style). Fires `engagement` events on visibility change / blur / navigation.
6. **Dedup**: Uses a `pageKey` (pathname + search) to prevent double-counting when frameworks call `pushState` then `replaceState` in the same tick, and seeds that key from the server-rendered page on first load.

### Configuration

Runtime config is injected by the layout into `window.analyticsConfig`:

```javascript
window.analyticsConfig = {
  useCookies: false,             // localStorage mode (cookieless)
  visitDurationMinutes: 30,      // 30-minute session window
  useBeaconForEvents: false,     // legacy flag; fetch keepalive is the active transport
  trackVisits: false,            // legacy flag; follow-up tracking is event-only
  initialPageviewTracked: true,  // set only when the server already counted this render
  initialPageKey: "/"            // server-seeded dedupe key for the current page
}
```

### Excluded paths

The tracker skips: `/admin`, `/app`, `/login`, `/logout`, `/register`, `/password`, `/ahoy`, `/cable`, static assets, and well-known files. These are hardcoded defaults in the tracker class.

### Transport

Events use `fetch` with `keepalive: true`, a JSON body, and `X-CSRF-Token` header when available. The tracker is intentionally fetch-first for more predictable Safari/WebKit behavior and simpler end-to-end testing.

## Server-Side Initial Pageviews

`app/controllers/concerns/server_side_pageview_tracking.rb` owns the first pageview for eligible public HTML renders by default.

### Eligibility rules

- `GET` requests only
- HTML document responses only
- skips redirects and `5xx` responses
- skips Inertia partial requests, XHR, admin/internal routes, asset-like paths, and well-known files
- skips speculative `prefetch` / `prerender` requests

### Dedupe model

- server tracks the first rendered pageview
- layout emits `initialPageviewTracked` / `initialPageKey`
- client tracker seeds its local state from those values and does not send the same first pageview again

## Server-Side: Ahoy Store

`config/initializers/ahoy.rb` customizes the default Ahoy database store:

### Visit enrichment (track_visit)

1. Sets `hostname` from request
2. Fixes `landing_page` when Ahoy records the API endpoint path instead of the actual page
3. Cleans self-referrals (same-site referring_domain → null)
4. Enriches geo data via MaxMind GeoIP when available
5. Falls back to Cloudflare `CF-IPCountry` header for country

### Event enrichment (track_event)

1. Extracts `screen_size` from viewport string and classifies into `Mobile/Tablet/Laptop/Desktop`
2. Corrects `landing_page` on the visit when the first event provides a real URL

### Client IP Resolution

`lib/client_ip.rb` extracts the real client IP from proxy headers. It only trusts `CF-Connecting-IP` and `X-Forwarded-For` when `REMOTE_ADDR` is a known Cloudflare proxy IP (verified against `config/cloudflare_trusted_proxies.txt`). This prevents header spoofing from untrusted sources.

```ruby
ClientIp.public(request)        # First public (non-private) IP from trusted chain
ClientIp.best_effort(request)   # First valid IP (may be private, for local dev)
ClientIp.country_hint(request)  # CF-IPCountry header value
```

The trusted proxy list is refreshed by running `ruby script/cloudflare/update_trusted_proxies.rb`.

## Query Pipeline

All dashboard API requests flow through the same pipeline:

```text
Browser → GET /admin/analytics/sources?period=7d&f=is,country,US
                    ↓
        Admin::Analytics::BaseController#prepare_query
          - parses period, filters (f=op,dim,clause), labels (l=key,val)
          - builds @query hash
                    ↓
        SourcesController#index
          - calls Ahoy::Visit.sources_payload(@query, limit:, page:, search:)
                    ↓
        Ahoy::Visit concern chain:
          Filters → Ranges → [Sources|Pages|Locations|Devices] → Metrics → Ordering → Pagination
                    ↓
        cache_for(key) { ... }  # 5-minute Rails.cache with SHA256 digest
                    ↓
        camelize_keys(payload)  # snake_case → camelCase for frontend
                    ↓
        render json: ...
```

### BaseController responsibilities

- `prepare_query` — merges URL params into a normalized query hash
- `shell_props(query)` — builds Inertia props for the dashboard shell (site context, user context, query, default query)
- `cache_for(key)` — SHA256-digest cache with 5-minute TTL
- `camelize_keys` — recursive snake→camel conversion for JSON responses
- `parsed_pagination` — limit/page with bounds (max 500)
- `normalized_search` — sanitized search term (max 100 chars)
- `parsed_order_by` — delegates to model whitelist

### Ahoy::Visit concerns

The Visit model includes 13 concerns that compose the query pipeline:

| Concern | Purpose |
|---|---|
| `Constants` | Channel classification rules, search engine list, social networks |
| `Filters` | Applies query filters (country, source, page, device, UTM, goals, etc.) to scopes |
| `Ranges` | Converts period strings (`day`, `7d`, `30d`, `month`, `custom`, etc.) to time ranges |
| `Series` | Time-series bucketing via PostgreSQL `generate_series` for the main graph |
| `Metrics` | Computes visitors, visits, pageviews, bounce rate, visit duration, views per visit |
| `Sources` | Groups by source/channel/UTM with the source catalog + custom alias YAML |
| `Pages` | Groups by landing page, entry page, or exit page |
| `Locations` | Groups by country/region/city with ISO metadata via `countries` gem |
| `Devices` | Groups by browser, OS, or screen size |
| `Ordering` | Whitelist-based column ordering with direction |
| `Pagination` | Limit/offset with `has_more` metadata |
| `CacheKey` | `analytics_data_version` counter for cache invalidation |
| `UrlLabels` | Human-readable labels for filter values (city names, region names) |

### Source classification

Traffic sources are classified into channels using this priority:

1. `utm_medium` / `utm_source` → channel mapping (e.g., `cpc` → Paid Search, `social` → Organic Social)
2. Custom source aliases from `config/analytics/custom_sources.yml`
3. Referring domain → `Analytics::SourceCatalog::SOURCE_MAP` regex matching
4. Fallback: `Direct / None`

### Filter syntax (Plausible-compatible)

Filters are passed as repeated `f` query params: `f=operator,dimension,clause`

| Operator | Example | Meaning |
|---|---|---|
| `is` | `f=is,country,US` | Country equals US |
| `is_not` | `f=is_not,browser,Chrome` | Browser is not Chrome |
| `contains` | `f=contains,page,/docs` | Page path contains /docs |

Labels use `l` params: `l=key,value` (e.g., `l=country,United States`)

## Frontend Dashboard

### Page structure

```text
/admin/analytics/reports     → ReportsController#index (Inertia page)
  └─ QueryProvider             URL ↔ query state sync
     └─ SiteContext + UserContext + TopStatsContext + LastLoadContext
        └─ AnalyticsDashboard
           ├─ TopBar            Period selector, filters, comparison toggle
           ├─ VisitorGraph      Chart.js time-series (main metric)
           └─ PanelTabs         Sources | Pages | Locations | Devices | Behaviors
              ├─ SourcesPanel   Source/channel/UTM breakdowns
              ├─ PagesPanel     Landing/entry/exit pages
              ├─ LocationsPanel Map + country/region/city tables
              ├─ DevicesPanel   Browser/OS/screen size tables
              └─ BehaviorsPanel Goals/funnels/custom properties
```

### URL state

The dashboard is fully URL-driven. All query state (period, filters, comparison, panel modes, graph metric) is serialized to URL params. The `QueryProvider` context syncs React state ↔ browser URL via `history.pushState`.

Panel-specific modes use namespaced params: `pages_mode=entry`, `devices_mode=operating-systems`, `sources_mode=utm-campaign`, `graph_metric=visit_duration`.

### API client

`app/frontend/pages/admin/analytics/api.ts` provides typed fetch functions for every endpoint:

```typescript
fetchTopStats(query, signal)
fetchMainGraph(query, { metric, interval }, signal)
fetchSources(query, { mode }, signal)
fetchPages(query, { mode }, signal)
fetchLocations(query, { mode }, signal)
fetchDevices(query, { mode }, signal)
fetchBehaviors(query, { mode, funnel }, signal)
fetchReferrers(query, { source }, signal)
fetchSearchTerms(query, extras, signal)
fetchListPage(path, query, extras, { limit, page, search, orderBy }, signal)
```

All functions accept an `AbortSignal` for cancellation on re-fetch.

### Detail dialogs

Clicking a row in any panel opens a `RemoteDetailsDialog` — a paginated, searchable, sortable modal that fetches data from the same API endpoint with `limit` and `page` params.

Dialog state is encoded in the URL path: `/admin/analytics/reports/_/sources` opens the sources detail dialog. This allows deep-linking and back/forward navigation.

## Live View

`/admin/analytics/live` shows real-time visitor activity.

### Data flow

```text
AnalyticsUpdateJob (every 30s via Solid Queue recurring)
  → AnalyticsLiveStats.build
    → current_visitors (5-min window)
    → today_sessions (count + yesterday comparison)
    → sparkline (hourly buckets, today vs yesterday)
    → sessions_by_location (top 5)
    → visitor_dots (lat/lng for globe)
  → ActionCable.server.broadcast("analytics", payload)
        ↓
  AnalyticsChannel (staff-only subscription)
        ↓
  React live page via @rails/actioncable consumer
```

### 3D Globe

The globe uses Three.js via `@react-three/fiber`:

- **Land layer** (`hex-land-layer.tsx`): Pre-computed H3 hex cells (`land-hex-cells.json`) rendered as conic polygon geometries. No runtime tessellation.
- **Highlight layer** (`hex-highlights.tsx`): Visitor dots converted to H3 cells at resolution 3, rendered as elevated colored hexagons
- **Shared geometry** (`lib/h3-hex-geometry.ts`): `buildMergedHexGeometry()` — takes H3 cell indices, builds shrunk conic polygons, merges into single BufferGeometry

The globe component is lazy-loaded (`React.lazy`) to avoid importing Three.js during SSR.

### Regenerating hex cells

If the land geometry source changes, regenerate the pre-computed cells:

```bash
npm run build:land-hex-cells
```

This runs `script/build_land_hex_cells.mjs` which reads `globe-data.json` (GeoJSON), tessellates with H3 at resolution 3, and writes `land-hex-cells.json`.

## MaxMind GeoIP

Optional. When `db/geo/GeoLite2-City.mmdb` exists, `MaxmindGeo.lookup(ip)` returns country, region, city, lat/lng for visit enrichment. Without it, the system falls back to Cloudflare's `CF-IPCountry` header for country-only geo.

The module (`config/initializers/maxmind.rb`) lazy-loads the database reader and validates IPs (rejects private, loopback, link-local).

## Funnels

Funnels are named sequences of steps (goal names or page paths). CRUD via `Admin::Analytics::FunnelsController`. Stored in `analytics_funnels` table with JSONB `steps` array.

The behaviors panel switches to funnel mode when `mode=funnels` is active, showing step-by-step conversion rates.

## Settings

`Admin::Analytics::SettingsController` manages runtime config stored in `analytics_settings`:

| Key | Type | Purpose |
|---|---|---|
| `gsc_configured` | boolean | Enables Google Search Console search terms panel |

## Adding a new analytics dimension

1. Add the column to `ahoy_visits` via a migration in `db/analytics_migrate/`
2. If the data comes from tracking, add it to `Ahoy::Store#track_visit` or `track_event` in `config/initializers/ahoy.rb`
3. Create or extend a concern under `app/models/ahoy/visit/` to add the grouping/filtering logic
4. Include the concern in `Ahoy::Visit`
5. Add a controller under `Admin::Analytics::` inheriting from `BaseController`
6. Add the route in `config/routes.rb` under the `namespace :analytics` block
7. Add a frontend panel component under `app/frontend/pages/admin/analytics/ui/`
8. Add the fetch function to `api.ts`
9. Add the panel tab to `panel-tabs.tsx`

## Adding a new tracked event

The tracker sends custom events via `sendEvent()`. To add a new auto-captured event:

1. Add detection logic in `initAutoCapture()` in `analytics.ts`
2. The event name becomes a goal in the behaviors panel automatically
3. No backend changes needed — events are stored as JSONB in `ahoy_events`

## Key files quick reference

| Category | Path |
|---|---|
| Tracker | `app/frontend/entrypoints/analytics.ts` |
| Ahoy store | `config/initializers/ahoy.rb` |
| Analytics config | `config/initializers/analytics.rb` |
| Source aliases | `config/analytics/custom_sources.yml` |
| Client IP | `lib/client_ip.rb`, `lib/trusted_proxy_ranges.rb` |
| MaxMind | `config/initializers/maxmind.rb` |
| Base controller | `app/controllers/admin/analytics/base_controller.rb` |
| Visit model | `app/models/ahoy/visit.rb` + `app/models/ahoy/visit/*.rb` |
| Event model | `app/models/ahoy/event.rb` |
| Live stats | `app/models/analytics_live_stats.rb` |
| Live job | `app/jobs/analytics_update_job.rb` |
| ActionCable | `app/channels/analytics_channel.rb` |
| Globe | `app/frontend/components/analytics/visitor-globe.tsx` |
| Hex geometry | `app/frontend/lib/h3-hex-geometry.ts` |
| Dashboard page | `app/frontend/pages/admin/analytics/reports/index.tsx` |
| API client | `app/frontend/pages/admin/analytics/api.ts` |
| Types | `app/frontend/pages/admin/analytics/types.ts` |
| Query context | `app/frontend/pages/admin/analytics/query-context.tsx` |
| Dashboard shell | `app/frontend/pages/admin/analytics/ui/analytics-dashboard.tsx` |
