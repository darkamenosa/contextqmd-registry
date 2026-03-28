# Analytics Architecture Guide

This document describes the self-hosted analytics system in this repo. It covers the data model, request pipeline, client-side tracker, live view, and the conventions needed to extend it safely.

## Overview

A Plausible-style analytics dashboard built on Ahoy. Ahoy visit/session ownership remains cookieless, while an app-owned first-party browser cookie provides weak continuity for analytics profile resolution. Runs in a dedicated PostgreSQL database isolated from primary app data. The admin dashboard at `/admin/analytics/reports` shows traffic stats; `/admin/analytics/live` shows real-time visitors on a 3D globe.

```text
Browser → analytics.ts tracker → /ahoy/visits + /ahoy/events
                                        ↓
                              Ahoy::Store (ahoy.rb initializer)
                                        ↓
                              analytics database (ahoy_visits, ahoy_events, analytics_profiles, analytics_profile_keys, analytics_profile_sessions, analytics_profile_summaries)
                                        ↓
                 Analytics::RequestQueryParser → Analytics::Query
                                        ↓
      Analytics::* / AnalyticsProfile::* domain objects + shallow Analytics::*Job jobs
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

**Tables**: `ahoy_visits`, `ahoy_events`, `analytics_funnels`, `analytics_settings`, `analytics_profiles`, `analytics_profile_keys`, `analytics_profile_sessions`, `analytics_profile_summaries`

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
| Identity | `visit_token`, `visitor_token`, `user_id`, `analytics_profile_id`, `browser_id` | Session + visitor tracking plus resolved profile continuity |
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

### analytics_profiles

One row per resolved analytics profile. This is the durable analytics-side actor record used to group visits over time without joining across the primary application database.

| Column | Purpose |
|---|---|
| `public_id` | External-safe profile identifier |
| `status` | `anonymous`, `identified`, or `merged` |
| `merged_into_id` | Canonical profile target when profiles are merged |
| `first_seen_at`, `last_seen_at`, `last_event_at` | Resolution lifecycle timestamps |
| `traits`, `stats` | Lightweight denormalized profile metadata |
| `resolver_version` | Resolution algorithm version used for the latest assignment |

### analytics_profile_keys

Strong identity keys that can safely stitch visits to a profile across sessions and devices.

| Column | Purpose |
|---|---|
| `analytics_profile_id` | Parent profile |
| `kind` | Strong key type like `identity_id`, `email_hash`, `stripe_customer_id` |
| `value` | Key value |
| `verified` | Whether the key is trusted enough for canonical resolution |
| `first_seen_at`, `last_seen_at` | When the key was observed |
| `metadata` | Optional source-specific metadata |

`browser_id` is intentionally not stored here. It is a weak browser-continuity signal stored on `ahoy_visits`, not a canonical identity key.

### analytics_profile_sessions

One row per projected profile-owned session, keyed back to the original `ahoy_visits` row. This is the profile journey read model used by profile-specific views.

| Column group | Columns | Purpose |
|---|---|---|
| Ownership | `analytics_profile_id`, `visit_id` | Canonical profile + backing visit |
| Timeline | `started_at`, `last_event_at`, `duration_seconds` | Session chronology |
| Activity | `events_count`, `pageviews_count`, `event_names`, `page_paths` | Session-level rollups |
| Context | `entry_page`, `exit_page`, `current_page`, `source`, `country`, `country_code`, `region`, `city`, `device_type`, `browser`, `os` | Latest session summary for journey/live/profile screens |

### analytics_profile_summaries

One row per profile summary. This is the denormalized directory/list read model optimized for profile search and profile overview payloads.

| Column group | Columns | Purpose |
|---|---|---|
| Ownership | `analytics_profile_id`, `latest_visit_id` | Canonical profile + latest backing visit |
| Timeline | `first_seen_at`, `last_seen_at`, `last_event_at` | Profile lifecycle summary |
| Identity | `display_name`, `email`, `search_text` | Searchable identity surface |
| Latest context | `latest_source`, `latest_current_page`, `latest_country_name`, `latest_country_code`, `latest_region`, `latest_city`, `latest_device_type`, `latest_browser`, `latest_os`, `latest_context` | Fast profile directory payload |
| Rollups | `total_visits`, `total_sessions`, `total_pageviews`, `total_events`, `devices_used`, `browsers_used`, `oses_used`, `sources_used`, `locations_used`, `top_pages` | Precomputed aggregate summary |

## Counting Semantics

The system currently has two different identity concepts:

- `visitor_token` = browser-scoped visitor identity used by most aggregate analytics metrics
- `analytics_profile_id` = resolved profile/person identity used by profile-centric analytics views

This means the current UI labels `Unique visitors` and `Live visitors` are browser-scoped, not person-scoped. A logged-in user opening the site in Chrome and Safari will currently count as:

- `2` visitors for top stats, most breakdowns, and live visitor counts
- `1` resolved profile/person when both visits resolve to the same strong identity key

Important implications:

- visitor counts are based on `visitor_token`, not `user_id` or `analytics_profile_id`
- profile merging does not retroactively change most report metrics today
- profile pages and live session cards can represent the same person across multiple browser sessions, while top-level visitor metrics still count those browser sessions separately

If product semantics need person-level counts, that change should happen in the reporting query layer by counting a merged identity key based on `analytics_profile_id` with fallback to `visitor_token`. Tracking and raw data collection do not need to change for that.

## Client-Side Tracker

`app/frontend/entrypoints/analytics.ts` — a standalone, framework-agnostic tracker injected into the application layout via `<%= vite_typescript_tag "analytics.ts" %>`.

### How it works

1. **Server-first initial pageview**: On eligible public HTML `GET` requests, Rails creates the visit and first `pageview` before the response is sent. The layout bootstraps only the initial `pageKey` and whether the current render was already counted.
2. **Browser continuity cookie**: Rails ensures a first-party `cq_analytics_browser_id` cookie exists. This browser id is separate from Ahoy visit/session ownership and is used only for anonymous continuity and profile resolution.
3. **Client follow-up tracking**: The standalone tracker seeds its dedupe/engagement state from that bootstrap and continues tracking SPA navigation, engagement, downloads, and outbound clicks.
4. **Event-only follow-up ingestion**: Subsequent tracking uses POST `/ahoy/events` only. Ahoy creates a new visit lazily on the next `pageview` when no recent visit exists.
5. **Engagement does not open a new visit**: `engagement` events extend an active visit, but are dropped when no recent visit exists. This matches Plausible-style session handling.
6. **Engagement tracking**: Tracks time-on-page and scroll depth (Plausible-style). Fires `engagement` events on visibility change / blur / navigation.
7. **Dedup**: Uses a `pageKey` (pathname + search) to prevent double-counting when frameworks call `pushState` then `replaceState` in the same tick, and seeds that key from the server-rendered page on first load.

### Configuration

Runtime config is injected by the layout into `window.analyticsConfig`:

```javascript
window.analyticsConfig = {
  useCookies: false,             // Ahoy visit/session cookies remain disabled
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
6. Persists `browser_id` from the first-party analytics cookie
7. Resolves `analytics_profile_id` when the profile tables are available

### Event enrichment (track_event)

1. Extracts `screen_size` from viewport string and classifies into `Mobile/Tablet/Laptop/Desktop`
2. Corrects `landing_page` on the visit when the first event provides a real URL
3. Re-runs profile resolution so late identity signals can upgrade an anonymous profile

### Profile resolution

Profile resolution is triggered from the Ahoy store and resolved through shallow analytics jobs that write `ahoy_visits.analytics_profile_id`.

Resolution priority:

1. strong keys from `analytics_profile_keys`
2. anonymous browser continuity via `ahoy_visits.browser_id`
3. create a new anonymous `analytics_profile`

Important constraints:

- strong keys win over browser continuity
- `browser_id` alone never upgrades or merges an already identified profile
- anonymous browser history may later merge into an identified profile when a strong key appears
- raw facts remain in `ahoy_visits` and `ahoy_events`; the profile is only the resolved owner

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
        Admin::Analytics::BaseController
          - delegates request parsing to Analytics::RequestQueryParser
          - builds Analytics::Query
                    ↓
        SourcesController#index
          - calls Analytics::SourcesDatasetQuery.payload(query: @query, ...)
                    ↓
        Analytics domain layer:
          Query → VisitScope / ReportMetrics / DatasetQuery::* → Storage adapter
                    ↓
        cache_for(key) { ... }  # 5-minute Rails.cache with SHA256 digest
                    ↓
        camelize_keys(payload)  # snake_case → camelCase for frontend
                    ↓
        render json: ...
```

### BaseController responsibilities

- `prepare_query` — parses URL params through `Analytics::RequestQueryParser` and builds `Analytics::Query`
- `shell_props(query)` — builds Inertia props for the dashboard shell (`site`, `query`, `defaultQuery`)
- `dashboard_boot_payload(query)` — preloads top stats, graph, panel payloads, and initial UI modes for the reports page
- `cache_for(key)` — SHA256-digest cache with 5-minute TTL
- `camelize_keys` — recursive snake→camel conversion for JSON responses
- `parsed_pagination` — limit/page with bounds (max 500)
- `normalized_search` — sanitized search term (max 100 chars)
- `parsed_order_by` — delegates to model whitelist

### Backend query objects

The reporting layer now lives primarily under `app/models/analytics/`:

| Object | Purpose |
|---|---|
| `Analytics::Query` | Semantic backend query contract |
| `Analytics::RequestQueryParser` | Backend URL/query parser |
| `Analytics::VisitScope` | Visit/pageview filtering and scoping |
| `Analytics::ReportMetrics` | Shared analytics calculations |
| `Analytics::*DatasetQuery` | Sources/pages/locations/devices/behaviors/referrers/search terms datasets |
| `Analytics::MainGraphQuery` | Main graph payload |
| `Analytics::TopStatsQuery` | Top stats payload |
| `Analytics::LiveState` | Public live analytics boundary |

### Current metric caveat

Most aggregate reporting queries still count distinct `visitor_token` values. In practice, this means:

- `Live visitors` is browser-scoped
- `Unique visitors` is browser-scoped
- many source, page, location, and behavior visitor counts are browser-scoped
- profile directory, profile journey, and live profile/session views are `analytics_profile_id`-aware

When changing labels or product copy, prefer:

- `visitor` only if browser-scoped counting is acceptable
- `browser` or `device` if the distinction needs to be explicit
- `profile`, `person`, or `identified person` for `analytics_profile_id`-based views

### Source classification

Traffic sources are classified into channels using this priority:

1. `utm_source` direct aliases and explicit source rules from `Analytics::SourceResolver`
2. `utm_source` or known labels canonicalized through `config/analytics/source_rules.yml`
3. Referring domain matched through `Analytics::SourceResolver` domain rules
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
  └─ props: site + query + defaultQuery + boot
     └─ AnalyticsDashboardProvider  site/top-stats/last-load state
        └─ QueryProvider            URL ↔ query state sync
           └─ AnalyticsDashboard
              ├─ TopBar            Period selector, filters, comparison toggle
              ├─ VisitorGraph      Chart.js time-series (main metric)
              ├─ SourcesPanel      Source/channel/UTM breakdowns
              ├─ PagesPanel        Landing/entry/exit pages
              ├─ LocationsPanel    Map + country/region/city tables
              ├─ DevicesPanel      Browser/OS/screen size tables
              └─ BehaviorsPanel    Goals/funnels/custom properties
```

`ReportsController#index` now ships a single boot payload for the initial dashboard render rather than forcing each panel to cold-fetch on mount. Thin wrapper hooks such as `site-context.tsx`, `top-stats-context.tsx`, and `last-load-context.tsx` read from `AnalyticsDashboardProvider`; they are no longer separate provider layers.

### URL state

The dashboard is fully URL-driven. All query state (period, filters, comparison, panel modes, graph metric, and dialog route hints) is serialized to URL params or route state. `QueryProvider` resolves the initial query from server props plus the current URL, canonicalizes the search string, and syncs updates through `location-store.ts`, `query-codec.ts`, and `report-url.ts`.

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
Analytics::LiveBroadcastJob (recurring + request-triggered coalescing)
  → Analytics::LiveState.build
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

`Admin::Analytics::LiveController#show` renders the page with `initialStats` from `Analytics::LiveState.build`. On the client, `live/show.tsx` composes extracted helpers such as `useLiveStats`, `useLiveLocationSearch`, `live-event-buffer`, `live-events-panel.tsx`, and `live-session-card.tsx` around the shared globe components.

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
3. Extend `Analytics::Query` / `Analytics::RequestQueryParser` if the dimension needs new filter semantics
4. Add or extend an analytics object under `app/models/analytics/` for grouping/filtering logic
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
| Source rules | `config/analytics/source_rules.yml` |
| Source resolver | `app/models/analytics/source_resolver.rb` |
| Client IP | `lib/client_ip.rb`, `lib/trusted_proxy_ranges.rb` |
| MaxMind | `config/initializers/maxmind.rb` |
| Base controller | `app/controllers/admin/analytics/base_controller.rb` |
| Reports controller | `app/controllers/admin/analytics/reports_controller.rb` |
| Live controller | `app/controllers/admin/analytics/live_controller.rb` |
| Visit model | `app/models/ahoy/visit.rb` + `app/models/ahoy/visit/*.rb` |
| Event model | `app/models/ahoy/event.rb` |
| Query parser + contract | `app/models/analytics/request_query_parser.rb`, `app/models/analytics/query.rb` |
| Dataset queries | `app/models/analytics/*_dataset_query.rb` |
| Live state | `app/models/analytics/live_state.rb` |
| Live job | `app/jobs/analytics/live_broadcast_job.rb` |
| ActionCable | `app/channels/analytics_channel.rb` |
| Globe | `app/frontend/components/analytics/visitor-globe.tsx` |
| Hex geometry | `app/frontend/lib/h3-hex-geometry.ts` |
| Dashboard page | `app/frontend/pages/admin/analytics/reports/index.tsx` |
| Dashboard state | `app/frontend/pages/admin/analytics/dashboard-context.tsx` |
| API client | `app/frontend/pages/admin/analytics/api.ts` |
| Types | `app/frontend/pages/admin/analytics/types.ts` |
| Query context | `app/frontend/pages/admin/analytics/query-context.tsx` |
| Query codec | `app/frontend/pages/admin/analytics/lib/query-codec.ts` |
| Report URL helpers | `app/frontend/pages/admin/analytics/lib/report-url.ts` |
| Dashboard shell | `app/frontend/pages/admin/analytics/ui/analytics-dashboard.tsx` |
| Live page | `app/frontend/pages/admin/analytics/live/show.tsx` |
