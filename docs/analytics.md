# Analytics Architecture Guide

This document describes the self-hosted analytics system in this repo. It covers the data model, request pipeline, client-side tracker, live view, and the conventions needed to extend it safely.

## Developer Onboarding

If you are new to this codebase, the simplest mental model is:

- `Analytics::Site` is the root object
- visits and events are the raw facts
- profiles are analytics-side identity read models
- `analytics_profile_keys` is the long-term identity map
- goals, funnels, and allowed event properties are site-scoped config
- search providers are site-scoped external integrations
- commerce providers are site-scoped external integrations
- revenue and attribution should be modeled as first-class facts, not hidden inside profile state

One practical strategy note:

- build the architecture broadly
- ship only the providers and UI this app actually uses now
- add future providers in vertical slices
- extract to an internal engine later instead of trying to publish a reusable package too early

### System Map

```text
host app
  -> Analytics::HostIntegration
  -> server-side pageview bootstrap
  -> /analytics/events
  -> Analytics::AhoyStore
  -> analytics DB
  -> Analytics::* dataset queries
  -> Admin::Analytics::* controllers
  -> /admin/analytics UI
```

### Database Shape

```text
analytics_sites
  -> analytics_site_boundaries
  -> ahoy_visits
       -> ahoy_events
       -> analytics_profiles
            -> analytics_profile_keys
            -> analytics_profile_sessions
            -> analytics_profile_summaries
  -> analytics_goals
  -> analytics_funnels
  -> analytics_allowed_event_properties
  -> search provider accounts / bindings / syncs / query facts
  -> commerce accounts / site bindings / customers / orders / payments / subscriptions
  -> attribution facts
```

### Directory Guide

- `app/models/analytics/`
  domain objects, resolvers, path builders, dataset queries, GSC logic
- `app/controllers/admin/analytics/`
  reports/live shell controllers and JSON dataset endpoints
- `app/controllers/concerns/admin/analytics/`
  shared site and GSC controller context
- `app/controllers/concerns/analytics/`
  host-app integration boundary
- `lib/analytics/`
  low-level tracking/runtime integration such as Ahoy store, browser identity, visit boundary
- `app/jobs/analytics/`
  profile projection, live broadcast, GSC sync jobs
- `app/frontend/pages/admin/analytics/`
  reports/live frontend
- `app/frontend/pages/admin/settings/analytics/`
  analytics settings UI

### Routing Modes

Single-site mode:

- one active `Analytics::Site`
- backend resolves that site automatically
- user-facing shell stays clean:
  - `/admin/analytics`
  - `/admin/analytics/live`
  - `/admin/settings/analytics`

Multi-site mode:

- more than one active `Analytics::Site`
- admin shell becomes explicit:
  - `/admin/analytics/sites/:site`
  - `/admin/analytics/sites/:site/live`
  - `/admin/settings/analytics?site=:site`
- tracking resolves by `host + path prefix`

Important distinction:

- shell pages may be singleton-style in single-site mode
- data/API routes remain site-scoped internally

### How To Extend It

When adding a new feature, decide which bucket it belongs to:

- identity
- report/query logic
- site config
- tracking/runtime behavior
- external integration
- commerce outcome
- attribution

Then follow these rules:

- put ownership on `analytics_site_id`
- prefer typed tables over generic settings blobs
- put report queries in `app/models/analytics/*_dataset_query`
- keep controllers thin
- put low-level tracking logic in `lib/analytics/`
- avoid making the host app know analytics internals
- keep business outcome facts separate from profile read models
- normalize reporting facts above provider-specific ingestion where practical

### Key Files To Read First

- [app/models/analytics/site.rb](../app/models/analytics/site.rb)
- [app/models/analytics/site_boundary.rb](../app/models/analytics/site_boundary.rb)
- [app/models/analytics/bootstrap.rb](../app/models/analytics/bootstrap.rb)
- [app/models/analytics/admin_site_resolver.rb](../app/models/analytics/admin_site_resolver.rb)
- [app/models/analytics/tracking_site_resolver.rb](../app/models/analytics/tracking_site_resolver.rb)
- [lib/analytics/ahoy_store.rb](../lib/analytics/ahoy_store.rb)
- [lib/analytics/ahoy_integration.rb](../lib/analytics/ahoy_integration.rb)
- [app/models/analytics/paths.rb](../app/models/analytics/paths.rb)

## Overview

A Plausible-style analytics dashboard built on Ahoy. Ahoy visit/session ownership remains cookieless, while an app-owned first-party browser cookie provides weak continuity for analytics profile resolution. Runs in a dedicated PostgreSQL database isolated from primary app data. The admin dashboard at `/admin/analytics` shows traffic stats; `/admin/analytics/live` shows real-time visitors on a 3D globe.

Public ownership rule:

- `Analytics` owns the public browser and HTTP contract
- `Ahoy` stays the internal tracking engine and persistence layer
- public endpoints should use `/analytics/*`, not `/ahoy/*`
- `ahoy_visits` and `ahoy_events` remain internal storage tables for now

```text
Browser → analytics.ts tracker → /analytics/events
                                        ↓
                 Ahoy::EventsController + Analytics::AhoyStore
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

**Tables today**: `ahoy_visits`, `ahoy_events`, `analytics_funnels`, `analytics_goals`, `analytics_allowed_event_properties`, `analytics_site_tracking_rules`, `analytics_settings`, `analytics_profiles`, `analytics_profile_keys`, `analytics_profile_sessions`, `analytics_profile_summaries`

**Tables planned next**:

- search provider accounts / bindings / syncs / normalized query facts
- commerce accounts / site bindings / customers / orders / order line items / payments / subscriptions
- attribution facts

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

Named conversion funnels with ordered typed step definitions stored as JSONB.

Recommended step types:

- `page_visit`
- `goal`

### analytics_settings

Legacy key-value store for lightweight runtime analytics configuration. New
site-owned analytics config should prefer typed records over adding more keys
here.

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

Longer term, this table should become the universal identity map for analytics. Good future `kind` values include:

- `identity_id`
- `email_hash`
- `app_user_id`
- `stripe_customer_id`
- `paddle_customer_id`
- `lemonsqueezy_customer_id`
- `shopify_customer_id`

Recommended matching order for future commerce/search linking:

1. exact visit/session/browser metadata supplied during checkout
2. strong app identity like `app_user_id`
3. provider customer id
4. verified email or email hash
5. unresolved facts remain unlinked until later reconciliation

Important rule:

- unresolved orders or payments are acceptable
- forcing weak profile links too early is worse than leaving a fact unresolved temporarily

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

## Future Commerce and Revenue Layer

This repo does not yet persist first-class revenue facts, but the architecture is intentionally moving that way.

Best future shape:

```text
analytics_sites
  -> profiles / profile_keys          # who
  -> visits / events                  # behavior
  -> search query facts               # search demand and SEO performance
  -> orders / payments / subscriptions # business outcomes
  -> attribution facts                # why value is assigned to traffic
```

Important rule:

- profiles should show orders and payments in the journey UI
- orders and payments should still be stored as first-class facts
- attribution should remain a derived reporting layer

### Why orders and payments both matter

Do not assume every provider is Stripe-like.

- Stripe, Paddle, and Lemon Squeezy are payment/subscription oriented
- Shopify is storefront/order oriented

So the right long-term commerce model is:

- commerce accounts
- commerce site bindings
- customers
- orders
- order line items
- payments
- subscriptions

This gives the reporting layer enough structure to answer:

- who purchased
- where they came from
- which pages convert
- which campaigns and sources bring revenue
- what products or plans are working

### Recommended future commerce tables

```text
analytics_commerce_accounts
analytics_commerce_site_bindings
analytics_customers
analytics_orders
analytics_order_line_items
analytics_payments
analytics_subscriptions
analytics_attribution_facts
```

Recommended interpretation:

- `analytics_orders`
  business transaction truth
- `analytics_commerce_site_bindings`
  maps an external store, merchant, or billing scope onto one analytics site
- `analytics_order_line_items`
  product or plan detail
- `analytics_payments`
  ledger-like money facts including refunds and renewals
- `analytics_subscriptions`
  durable subscription state
- `analytics_attribution_facts`
  derived reporting credit by source/page/campaign/keyword/etc

### Edge cases the future model must handle

- guest checkout with no logged-in app user
- delayed provider webhooks
- same customer returning on another device
- one order with multiple payment attempts
- partial refunds
- chargebacks
- subscription renewals months later
- sites with no commerce provider at all
- one site with multiple providers
- one provider account reused across multiple sites later

### Exact vs estimated revenue attribution

Treat these as different classes of truth:

- exact enough:
  - purchaser
  - source
  - referrer
  - campaign
  - landing page
  - country
  - device
  - order count
  - revenue
- estimated:
  - keyword revenue
  - keyword conversion rate

Why:

- search providers expose aggregate query performance
- they do not provide exact per-visit keyword truth for every purchase

So future keyword revenue should be labeled as estimated or inferred.

Recommended attribution rollout:

- ship `last_touch` first for exact-enough source/page/campaign revenue
- add `estimated_search` for query-level keyword revenue
- add `first_touch` or `linear` later only when product needs them

### Search provider normalization

Google Search Console is the first provider, not the final reporting model.

Longer term, normalized reporting should read from provider-neutral search query facts with columns like:

- `provider`
- `date`
- `query`
- `page`
- `country`
- `device`
- `clicks`
- `impressions`
- `position`

That is the cleanest path to future Bing support without forcing report query rewrites.

Recommended v1 practical rule:

- implementation can stay Google-first
- reporting contracts should move toward provider-neutral search facts
- new report/query code should avoid spreading Google-only assumptions when a normalized shape will do
- cached provider facts should keep one canonical `page` value for reporting rather than storing both raw and normalized page variants

Recommended v1 search reports:

- query performance
- page performance
- country performance
- device performance
- stronger Google organic drilldowns in reports
- inferred `Search Terms Preview` in profile/session views

Recommended v1 non-goals:

- exact per-visit keyword truth
- live search-provider dashboards
- cross-provider blended ranking semantics

Recommended future search provider tables:

```text
analytics_search_provider_accounts
analytics_search_site_bindings
analytics_search_syncs
analytics_search_query_facts
```

Interpretation:

- provider accounts store OAuth/API credentials and account state
- site bindings store which external property belongs to which analytics site
- syncs track import windows and failures
- query facts are the provider-neutral reporting facts

Current implementation note:

- Google-specific tables are still fine as the first implementation step
- the long-term reporting contract should normalize above them
- Bing should be added later by implementing the same reporting contract, not by redesigning the search model

### Storage direction

Long-term split:

- Postgres control plane:
  - sites
  - boundaries
  - settings
  - provider accounts / bindings
  - sync metadata
- fact store:
  - visits
  - events
  - search query facts
  - orders
  - payments
  - subscriptions
  - attribution facts

Today the fact store is still Postgres. Later it can move behind ClickHouse adapters without changing the control plane.

### Privacy and operations notes

- provider credentials should always be encrypted
- webhook ingestion must be idempotent
- event ids or external ids should be used for replay-safe upserts
- privacy deletion or redaction flows from providers should be handled explicitly
- keep original provider identifiers and original currency values for auditability

## Client-Side Tracker

`app/frontend/entrypoints/analytics.ts` — a standalone, framework-agnostic tracker injected into the application layout via `<%= vite_typescript_tag "analytics.ts" %>`.

### How it works

1. **Server-first initial pageview**: On eligible public HTML `GET` requests, Rails creates the visit and first `pageview` before the response is sent. The layout bootstraps only the initial `pageKey` and whether the current render was already counted.
2. **Browser continuity cookie**: Rails ensures a first-party `cq_analytics_browser_id` cookie exists. This browser id is separate from Ahoy visit/session ownership and is used only for anonymous continuity and profile resolution.
3. **Client follow-up tracking**: The standalone tracker seeds its dedupe/engagement state from that bootstrap and continues tracking SPA navigation, engagement, downloads, and outbound clicks.
4. **Event-only follow-up ingestion**: Subsequent tracking uses POST `/analytics/events` only. Ahoy creates a new visit lazily on the next `pageview` when no recent visit exists.
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

For external installs, admin settings should generate a public snippet that points
to `/analytics/script.js`. The public contract should stay small:

```html
<script
  defer
  src="https://analytics.example.com/analytics/script.js"
  data-website-id="site_xxx"
></script>
```

That loader should normalize `data-website-id` into the same
`window.analyticsConfig` shape before it imports the real Vite tracker bundle.
Tracking rules should come from backend-owned bootstrap, not HTML attributes.
Any signed site token should be an internal runtime/bootstrap detail, not the
public HTML contract.

### Excluded paths

Analytics owns one set of system defaults in code and derives the runtime lists
from that source. Today that means:

- tracker/bootstrap defaults skip: `/admin`, `/.well-known`, `/analytics`,
  `/ahoy`, `/cable`
- server-side pageview enforcement also skips internal transport and platform
  paths like `/api`, `/rails/*`, `/assets/*`, `/up`, `/jobs`, and `/webhooks`
- reporting cleanup treats `/analytics`, `/ahoy`, `/cable`, `/rails/*`,
  `/assets/*`, `/up`, `/jobs`, and `/webhooks` as internal
These should not become separate frontend user config. The best model is:

- analytics owns system/internal excludes by default
- user-defined include/exclude rules live once in analytics settings, stored in
  the typed `analytics_site_tracking_rules` record for each site
- bootstrap sends the effective rules to the tracker
- backend still enforces them for correctness

### Transport

Events use `fetch` with `keepalive: true`, a JSON body, and `X-CSRF-Token` header when available. The tracker is intentionally fetch-first for more predictable Safari/WebKit behavior and simpler end-to-end testing.

External snippet installs use:

- `POST /analytics/bootstrap` to validate the embed and mint runtime config
- `OPTIONS /analytics/bootstrap` and `OPTIONS /analytics/events` for CORS
- `POST /analytics/events` for event ingestion

Site ownership should still resolve server-side through `website_id` lookup for
bootstrap, internal site attestation for events, and strict boundary
resolution.

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

`Analytics.setup` now owns the public host setup surface. Ahoy is an internal implementation detail installed from `config/initializers/analytics.rb`, with the tracking/runtime wiring living in `lib/analytics/*`:

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

Page filter note:

- analytics report filters should treat page values as canonical normalized paths
- malformed non-path page filter values should be normalized consistently across report endpoints rather than handled ad hoc per query

## Frontend Dashboard

### Page structure

```text
/admin/analytics             → ReportsController#index (Inertia page)
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

Dialog state is encoded in the URL path: `/admin/analytics/_/sources` opens the sources detail dialog. This allows deep-linking and back/forward navigation.

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
  → ActionCable.server.broadcast("analytics:<site_public_id>", payload)
        ↓
  Live controller renders signed subscription token for resolved site scope
        ↓
  AnalyticsChannel verifies token, resolves the scoped stream, subscribes
        ↓
  React live page via @rails/actioncable consumer
```

`Admin::Analytics::LiveController#show` renders the page with `initialStats` from `Analytics::LiveState.build` plus a signed live subscription token for the already-resolved analytics scope. On the client, `live/show.tsx` composes extracted helpers such as `useLiveStats`, `useLiveLocationSearch`, `live-event-buffer`, `live-events-panel.tsx`, and `live-session-card.tsx` around the shared globe components.

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

Funnels are named sequences of ordered, positive milestones. CRUD lives in
`Admin::Analytics::FunnelsController`. They are stored in `analytics_funnels`
with a typed JSONB `steps` array.

Recommended step schema:

```json
[
  {
    "name": "Visit landing page",
    "type": "page_visit",
    "match": "equals",
    "value": "/"
  },
  {
    "name": "Signup",
    "type": "goal",
    "match": "completes",
    "goal_key": "signup"
  }
]
```

Recommended funnel step types:

- `page_visit`
  - represents reaching a page URL/path
  - matchers should stay positive only in v1:
    - `equals`
    - `contains`
    - `starts_with`
    - `ends_with`
- `goal`
  - represents completing a tracked goal/custom event
  - v1 matcher should be only:
    - `completes`

Important rules:

- funnels should mix page steps and goal steps naturally
- step names are presentation labels, not primary identifiers
- goal steps should reference a stable goal key/name, not only free-form text
- funnel steps should stay positive and time-ordered
- avoid negative matchers like `does_not_equal` in funnels; they are ambiguous in
  ordered conversion paths
- v1 funnels should stay visit/browser scoped unless the product explicitly adds
  a separate profile-based funnel mode later

Why negative goal steps stay out:

- `does_not_complete` is not a milestone, it is an absence
- absence needs an evaluation window such as:
  - by end of visit
  - within N minutes after step X
  - before the next step
  - within the reporting range
- each window produces different numbers, so it should not be hidden inside a
  normal funnel step

Recommended v2 design for non-completion and exclusions:

- keep funnels as positive ordered milestones
- add optional funnel-level exclusion rules, not negative steps
- add optional abandonment conditions evaluated relative to a positive step

Example future shape:

```json
{
  "name": "Signup funnel",
  "steps": [
    { "type": "page_visit", "match": "equals", "value": "/pricing" },
    { "type": "goal", "match": "completes", "goal_key": "signup" }
  ],
  "exclusions": [
    {
      "scope": "entire_funnel",
      "type": "goal",
      "match": "completes",
      "goal_key": "internal_test"
    }
  ],
  "abandonment_rules": [
    {
      "after_step": 1,
      "type": "goal",
      "match": "not_completed_within_session",
      "goal_key": "signup"
    }
  ]
}
```

Meaning:

- `exclusions` remove visits/sessions from the funnel population entirely
- `abandonment_rules` describe a separate analysis like:
  - reached step X
  - did not complete goal Y within the same visit/session

That is a better product boundary than adding `does_not_complete` as a normal
step matcher.

Recommended builder UX:

- when adding a step, choose:
  - `Page visit`
  - `Goal`
- for `Page visit`, select a matcher and a path value
- for `Goal`, search/select from existing goals
- suggested steps may come from:
  - common pages such as landing/pricing/signup
  - existing goals
- do not reduce funnel creation to a plain list of step labels

Recommended funnel visualization UX:

- the behaviors panel should render funnels as a horizontal journey, not a plain
  list or stacked cards
- each step should show:
  - step name
  - visitors who reached that step
  - conversion from funnel start
- each gap between steps should show dropoff percentage
- the overall conversion rate should be prominent in the panel header or top
  right summary
- hover details should stay lightweight in v1:
  - visitors at this step
  - dropoff from previous step
  - conversion from start
- v1 should use the existing funnel payload only; do not invent fake revenue,
  attribution, or source breakdowns inside the tooltip

The behaviors panel switches to funnel mode when `mode=funnels` is active,
showing a horizontal step-by-step conversion flow instead of a generic list.

## Settings

`Admin::Analytics::SettingsController` manages the remaining lightweight runtime
config:

| Key | Type | Purpose |
|---|---|---|
| `analytics_site_tracking_rules` | typed record | Site-scoped include/exclude tracking rules merged with system defaults |

Longer term, settings should continue moving away from generic key/value state and toward typed site-scoped resources for:

- search provider connections
- commerce provider connections
- goals
- funnels
- allowed/custom event properties

For a future SaaS product, this means:

- analytics remains site-rooted
- integrations are optional per site
- one site can be traffic-only
- another site can enable search + commerce + attribution

For the current app, the product/UI priority should stay narrower:

- make Google Search Console setup easy
- make search reporting useful
- keep current single-site UX simple
- avoid exposing unused commerce setup until a real site needs it

## Adding a new analytics dimension

1. Add the column to `ahoy_visits` via a migration in `db/analytics_migrate/`
2. If the data comes from tracking, add it to `Ahoy::Store#track_visit` or `track_event` in `lib/analytics/ahoy_store.rb`
3. Extend `Analytics::Query` / `Analytics::RequestQueryParser` if the dimension needs new filter semantics
4. Add or extend an analytics object under `app/models/analytics/` for grouping/filtering logic
5. Add a controller under `Admin::Analytics::` inheriting from `BaseController`
6. Add the route in `config/routes.rb` under the `namespace :analytics` block
7. Add a frontend panel component under `app/frontend/pages/admin/analytics/ui/`
8. Add the fetch function to `api.ts`
9. Add the panel tab to `panel-tabs.tsx`

## Adding a new provider integration

When adding a new search or commerce provider:

1. keep the provider site-scoped through `analytics_site_id`
2. store credentials and sync state in typed control-plane tables
3. normalize reporting facts so queries stay provider-neutral where practical
4. keep provider-specific ingestion details out of the main report query layer
5. keep profile linking explicit through `analytics_profile_keys`, customers, or other stable external identifiers

Examples:

- `google`, `bing` for search providers
- `stripe`, `paddle`, `lemonsqueezy`, `shopify` for commerce providers

Provider-specific implementation notes:

- Stripe / Paddle / Lemon Squeezy are usually payment/subscription-first
- Shopify is order/storefront-first
- do not force all providers into one payment-only mental model
- normalize above provider-specific ingestion, not below it

Recommended delivery strategy:

- add one provider at a time
- ship one complete vertical slice at a time
- validate the shared model with real usage before widening to the next provider

## Goal Tracking Contract

The current backend goal model is already stronger than a plain event counter:

- `Analytics::Goal` stores typed goal definitions
- `Analytics::Goals` owns goal matching logic
- `Analytics::AllowedEventProperty` defines which custom properties may be
  retained and queried safely

The public developer-facing tracking surface is partially implemented.

Recommended contract:

### 1. Public JavaScript API

The tracker now exposes one simple browser API:

```javascript
window.analytics("signup")
window.analytics("initiate_checkout", { plan: "pro" })
```

Use it for custom events that should map into goals and behavior reporting.

These calls do not silently create managed goals in the database. Instead:

- recent custom event names are detected automatically
- `Settings > Analytics > Goals` shows them as one-click suggestions
- users can add one or all detected events as managed goals without typing
- managed goals remain the stable source of truth for reporting and funnels

### 2. Declarative HTML API

The tracker also supports a simple HTML convention for sites that do not want
to write custom JavaScript:

```html
<button
  data-analytics-goal="signup"
  data-analytics-prop-plan="pro"
>
  Start free trial
</button>
```

This compiles down to the same runtime event pipeline as the JS helper.

### 3. Server-Side Event Tracking

Longer term, analytics should also support a server-side event/goal API for
host apps that want more accurate or privileged tracking. That API should write
into the same event/goal system, not invent a second concept of goals.

### 4. Revenue Is Not A Custom Goal

Purchases, renewals, refunds, and revenue should remain first-class commerce
facts. They may appear in conversion reporting later, but they should not be
modeled as generic custom goals.

## Adding a new auto-captured event

The tracker sends custom events via `sendEvent()`. To add a new auto-captured event:

1. Add detection logic in `initAutoCapture()` in `analytics.ts`
2. The event name becomes a goal in the behaviors panel automatically
3. No backend changes needed — events are stored as JSONB in `ahoy_events`

## Key files quick reference

| Category | Path |
|---|---|
| Tracker | `app/frontend/entrypoints/analytics.ts` |
| Analytics setup | `config/initializers/analytics.rb`, `lib/analytics.rb` |
| Ahoy store | `lib/analytics/ahoy_store.rb`, `lib/analytics/ahoy_integration.rb` |
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

## Host config defaults

The host app should keep analytics setup small and explicit in
`config/initializers/analytics.rb`.

Current defaults now cover:

- `mode`
  single-site by default, multi-site only when the host app opts in
- `default_site.host`
  optional override for singleton bootstrap; falls back to the current request host
- `default_site.name`
  optional display name override; falls back to the resolved host
- `google_search_console.client_id`
- `google_search_console.client_secret`
- `google_search_console.callback_path`
  defaults to `/admin/settings/analytics/google_search_console/callback`

Example: single-site host app

```ruby
Analytics.setup do |config|
  config.mode = :single_site
  config.default_site.host = "localhost"
  config.default_site.name = "contextqmd.com"
  config.google_search_console.client_id =
    ENV["GOOGLE_SEARCH_CONSOLE_CLIENT_ID"]
  config.google_search_console.client_secret =
    ENV["GOOGLE_SEARCH_CONSOLE_CLIENT_SECRET"]
end
```

Example: multi-site host app

```ruby
Analytics.setup do |config|
  config.mode = :multi_site
  config.google_search_console.client_id =
    ENV["GOOGLE_SEARCH_CONSOLE_CLIENT_ID"]
  config.google_search_console.client_secret =
    ENV["GOOGLE_SEARCH_CONSOLE_CLIENT_SECRET"]
end
```

For multi-site apps, actual sites and boundaries belong in the database, not in
the initializer.

For single-site apps, the intended flow is:

1. configure analytics defaults once
2. visit `Settings > Analytics`
3. initialize the default site if it has not been bootstrapped yet
4. connect Google Search Console using the callback URL shown in settings

This keeps request-time resolution read-only while still giving the host app an easy setup path.

## Google Search Console OAuth shape

Google Search Console should use one stable callback URL:

- `/admin/settings/analytics/google_search_console/callback`

The callback path should not include `:site`.

Instead:

1. the connect action stores the target analytics site in signed session/state
2. Google redirects back to the single callback URL
3. the callback verifies the returned OAuth state
4. the app loads the intended analytics site from session/state
5. the connection is attached to that site

This is cleaner because:

- Google Cloud only needs one authorized redirect URI
- single-site apps do not leak site ids into OAuth setup
- multi-site apps still work without changing the redirect URI
