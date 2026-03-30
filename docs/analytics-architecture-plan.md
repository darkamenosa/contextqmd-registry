# Analytics Architecture Plan

This document captures the agreed plan for evolving the analytics system so it can:

- support Google Search Console cleanly
- support future Bing and other search-performance providers cleanly
- support future commerce and revenue attribution cleanly
- remain reusable across other projects
- keep room for a future ClickHouse-backed fact store
- follow the existing Rails/Fizzy-style structure in this codebase

It is intentionally a forward-looking design document. For the current implementation, see [analytics.md](./analytics.md).

## Goals

1. Introduce a first-class analytics owner so analytics is not singleton/global.
2. Keep the analytics module reusable across products with different tenancy models.
3. Separate analytics configuration from external integrations and secrets.
4. Make the reporting layer adapter-backed so Postgres can be replaced later with ClickHouse for fact queries.
5. Add Google Search Console as a site-level integration, not as a generic boolean setting.
6. Prepare for site-scoped commerce analytics so future projects can answer questions like:
   - who purchased
   - where they came from
   - what source, campaign, page, or keyword likely drove revenue

## Current State

Today the analytics system is effectively global:

- `analytics_settings` is a singleton-style key/value table
- `analytics_goals` and `analytics_funnels` are globally unique
- report queries start from `Ahoy::Visit.all`
- the reports shell uses `request.host` for context, but there is no first-class analytics site/project record

This is acceptable for one app, but it is the wrong foundation for reusable analytics.

## Key Decision

Introduce `Analytics::Site` as the root aggregate for analytics.

This root lives in the analytics database and represents one tracked reporting property.

Why `Analytics::Site`:

- the current tracker is web-property oriented
- Google Search Console is site/property oriented
- it avoids coupling analytics internals to the host app's `Account`
- it still allows different host apps to map their own ownership models into analytics

Important constraint:

- one `Analytics::Site` should represent one reporting property with its own goals, funnels, and Google Search Console connection
- if two surfaces need different goals or a different Search Console property, they should usually be different analytics sites

## High-Level Architecture

### Runtime Context

Analytics should keep its own current context instead of storing feature-specific state on the host app's global `Current`.

Recommended split:

- `Current`
  - app/account/user/request context
- `Analytics::Current`
  - `site`
  - `site_boundary`

Reasoning:

- this keeps analytics internals reusable across host apps
- it avoids polluting the host app's global current context with analytics-specific state
- it makes it easier to move the analytics module into another app later

All analytics-owned scopes, queries, and integrations should default to `Analytics::Current.site`, not `Current.analytics_site`.

### Bootstrap vs Resolution

Bootstrap and request-time site resolution should be separate concerns.

Recommended services:

- `Analytics::Bootstrap`
- `Analytics::AdminSiteResolver`
- `Analytics::TrackingSiteResolver`
- `Analytics::Paths`

Responsibilities:

- `Analytics::Bootstrap.ensure_default_site!(host:)`
  - create the default singleton site once when analytics is operating in single-site mode
- `Analytics::AdminSiteResolver.resolve!(explicit_site_id: nil, request: nil)`
  - explicit site id wins
  - if there is one active analytics site, return it
  - if there are multiple sites, require explicit selection
  - admin resolution must not infer the site from `/admin/...` request paths
- `Analytics::TrackingSiteResolver.resolve!(host:, path: nil, url: nil)`
  - if there is one active analytics site, return it
  - if there are multiple sites, resolve by configured boundary
  - tracking resolution is the only place that should look at tracked URLs and path prefixes
- `Analytics::Paths`
  - own all analytics/settings URLs
  - use Rails route helpers only
  - hide single-site vs multi-site branching from controllers

Avoid hidden bootstrapping in normal read paths like `resolve_for_host(..., autocreate: true)`.
Avoid string interpolation for analytics routes in controllers.

### Control Plane

Keep these in Postgres in the analytics database:

- `analytics_sites`
- `analytics_site_boundaries`
- `analytics_goals`
- `analytics_funnels`
- `analytics_allowed_event_properties`
- `analytics_search_provider_accounts`
- `analytics_search_site_bindings`
- `analytics_search_syncs`
- `analytics_commerce_accounts`
- `analytics_commerce_site_bindings`
- `analytics_customers`

These are low-volume, transactional, admin-managed records.

### Fact Plane

The high-volume analytics facts should be treated as adapter-backed:

- visits
- events
- normalized search query facts
- commerce outcome facts
- attribution facts
- future rollups

Today they can stay in Postgres.
Later they can move to ClickHouse behind `*::Postgres` and `*::Clickhouse` adapters.

Important: this is not a full-database swap. Postgres remains the control plane even if ClickHouse becomes the fact store.

## Recommended Data Model

### New Root Table

`analytics_sites`

Suggested columns:

- `id`
- `public_id`
- `owner_type`
- `owner_key`
- `name`
- `canonical_hostname`
- `time_zone`
- `status`
- `metadata`
- timestamps

Notes:

- `owner_type` + `owner_key` lets host apps map their own tenant model into analytics without cross-database joins
- `public_id` gives an external-safe identifier for routes or APIs later

### Site Boundaries

`analytics_site_boundaries`

Suggested columns:

- `id`
- `analytics_site_id`
- `host`
- `path_prefix`
- `priority`
- `primary`
- timestamps

This exists because:

- hostnames change
- one logical site can have multiple valid hosts
- the same host can serve multiple analytics sites under different path prefixes

Examples:

- `example.com/`
- `example.com/docs`
- `example.com/blog`
- `docs.example.com/`

Resolution rules:

1. trusted explicit tracker-supplied site key may win
2. exact configured boundary match on host + path prefix wins
3. longest matching path prefix wins
4. host-only fallback may be used
5. unresolved traffic should be rejected or routed to an explicit unresolved bucket

The chosen boundary should be persisted on ingested facts for auditability.

Trust model for site keys:

- a public client must not be allowed to arbitrarily claim any analytics site
- an explicit site key should only override boundary resolution if it is trusted
- trusted site keys should be server-bootstrapped or signed
- if an explicit site key and resolved boundary disagree, the request should be rejected and logged for investigation

Boundary resolution should remain authoritative when no trusted site key is present.

Normalization rules:

- `host` must be normalized to lowercase
- `path_prefix` must start with `/`
- `path_prefix` must not have a trailing slash unless it is exactly `/`
- boundary matching should use normalized request paths

Recommended constraints:

- unique index on `(host, path_prefix)`
- longest matching prefix wins by default
- `priority` should exist only as a tiebreaker for exceptional collisions, not as the primary matching rule
- avoid introducing a free-form `match_kind` unless concrete use cases appear

### Scope Existing Analytics Tables

Add `analytics_site_id` to:

- `ahoy_visits`
- `ahoy_events`
- `analytics_profiles`
- `analytics_profile_keys`
- `analytics_profile_sessions`
- `analytics_profile_summaries`
- `analytics_goals`
- `analytics_funnels`

Add `analytics_site_boundary_id` to:

- `ahoy_visits`
- `ahoy_events`

Rationale:

- event ownership should be explicit from day one
- this makes ETL and a future ClickHouse move significantly easier
- it avoids mandatory joins to visits for all fact queries

### Replace Generic Property Settings

Do not continue using a generic global `analytics_settings` table for important site-scoped analytics definitions.

Use typed tables where possible:

- goals: `analytics_goals`
- funnels: `analytics_funnels`
- allowed event properties: `analytics_allowed_event_properties`

`analytics_settings` can remain for lightweight operational flags if needed, but it should not remain the primary home for site-specific analytics configuration.

### Identity and Profiles

Profiles remain the answer to `who`, but they should not become the only place where business outcomes live.

Recommended rule:

- `analytics_profiles` is the identity and journey root
- `analytics_profile_keys` is the universal identity map
- purchases, renewals, refunds, and orders should remain first-class facts linked to profiles, not only embedded inside profile state

Recommended `analytics_profile_keys.kind` expansion:

- `identity_id`
- `email_hash`
- `app_user_id`
- `stripe_customer_id`
- `paddle_customer_id`
- `lemonsqueezy_customer_id`
- `shopify_customer_id`

This makes it possible to stitch:

- anonymous browsing
- logged-in identities
- guest checkout
- delayed provider webhooks
- later renewals and refunds

Recommended profile-linking strategy for future commerce and search integrations:

1. exact visit/session/browser metadata supplied at checkout or conversion time
2. strong app identity keys like `app_user_id`
3. provider customer identifiers like `stripe_customer_id` or `shopify_customer_id`
4. verified email or email hash
5. unresolved facts remain unlinked until a later reconciliation pass

Important constraints:

- do not force every order or payment onto a profile at ingest time
- allow unresolved commerce facts to exist temporarily without breaking reporting
- later resolution should be idempotent and auditable
- `browser_id` alone should never be treated as a strong commercial identity key

### Search Provider Accounts

Do not hardcode long-term reporting architecture around Google-only tables.

Recommended control-plane tables:

- `analytics_search_provider_accounts`
- `analytics_search_site_bindings`
- `analytics_search_syncs`

Why account + binding:

- one Google account may access many Search Console properties
- one Bing Webmaster account may access many sites
- one analytics site should bind to the specific external property it wants to report on
- a future SaaS may let one workspace operator connect one provider account and map multiple managed sites to it

Suggested `analytics_search_provider_accounts` columns:

- `id`
- `analytics_site_id`
- `provider`
- `status`
- `account_email`
- `access_token`
- `refresh_token`
- `expires_at`
- `metadata`
- timestamps

Suggested `analytics_search_site_bindings` columns:

- `id`
- `analytics_site_id`
- `analytics_search_provider_account_id`
- `provider`
- `property_identifier`
- `property_type`
- `active`
- `last_verified_at`
- `metadata`
- timestamps

Recommended provider values:

- `google`
- `bing`

Recommended account + binding rules:

- provider accounts store credentials and account-level state
- site bindings store which external property belongs to which `analytics_site`
- bindings should support historical inactive rows instead of destructive replacement
- one site may have at most one active binding per provider at a time
- one provider account may be reused by multiple site bindings

### Google Search Console Connection

The current implementation may still use Google-specific tables first. That is acceptable for phase one, but the long-term reporting shape should normalize above provider-specific ingestion.

`analytics_google_search_console_connections`

Suggested columns:

- `id`
- `analytics_site_id`
- `google_email`
- `access_token`
- `refresh_token`
- `expires_at`
- `property_identifier`
- `property_type`
- `last_verified_at`
- `status`
- `metadata`
- timestamps

Security:

- use Rails Active Record Encryption for token columns
- do not store OAuth secrets in `analytics_settings`

Recommended cardinality rules:

- allow multiple historical connection rows per site
- enforce at most one active Google Search Console connection per `analytics_site_id`
- enforce at most one active property selection per site

This keeps reconnect and re-link flows explicit without losing history.

### Search Sync Metadata

Longer term, sync metadata should normalize to:

- `analytics_search_syncs`

Suggested columns:

- `id`
- `analytics_site_id`
- `analytics_search_site_binding_id`
- `provider`
- `from_date`
- `to_date`
- `started_at`
- `finished_at`
- `status`
- `error_message`
- timestamps

The current Google-specific sync table is acceptable as a first step, but future providers should not force report queries to know about provider-specific sync storage.

Recommended sync behavior:

- syncs must be idempotent
- sync state should be explicit: `pending`, `running`, `succeeded`, `failed`
- partial date-range re-sync should be safe
- sync rows should persist failure details for ops visibility
- the fact rows loaded by a sync should remain traceable to that sync for debugging and replay

### Google Search Console Sync Metadata

`analytics_google_search_console_syncs`

Suggested columns:

- `id`
- `analytics_google_search_console_connection_id`
- `from_date`
- `to_date`
- `started_at`
- `finished_at`
- `status`
- `error_message`
- timestamps

### Cached Google Search Console Facts

`analytics_google_search_console_query_rows`

Suggested columns:

- `id`
- `analytics_site_id`
- `analytics_google_search_console_sync_id`
- `date`
- `search_type`
- `query`
- `page`
- `country`
- `device`
- `clicks`
- `impressions`
- `position_impressions_sum`
- timestamps

Derived values:

- `ctr` should be computed from `clicks / impressions`
- `position` should be computed from `position_impressions_sum / impressions`

Rationale:

- `ctr` is derived and should not be stored as a base fact
- average position is not safely additive across rows or time windows unless a weighted component is stored

This table should be treated as fact data. It can remain in Postgres initially and later move behind a ClickHouse adapter.

Recommended grain:

- one row per `analytics_site_id + date + search_type + query + page + country + device`

Recommended constraints:

- unique index on `(analytics_site_id, date, search_type, query, page, country, device)`
- keep `page` canonical at the fact layer; store the normalized reporting path, not provider-specific URL variants
- if exact page-filtered reports become hot, add a lookup index shaped like `(analytics_site_id, search_type, page, date)`

Rationale:

- syncs must be idempotent
- partial re-syncs should be safe
- the source sync that produced a fact row should be traceable
- canonical `page` keeps reporting queries simple and avoids dual raw/normalized page columns for the same fact

### Normalized Search Query Facts

For provider-neutral reporting, the long-term fact table should be:

`analytics_search_query_facts`

Suggested columns:

- `id`
- `analytics_site_id`
- `provider`
- `analytics_search_sync_id`
- `date`
- `query`
- `page`
- `country`
- `device`
- `clicks`
- `impressions`
- `position_impressions_sum`
- timestamps

Derived values:

- `ctr` from `clicks / impressions`
- `position` from `position_impressions_sum / impressions`

Rationale:

- Google and Bing both naturally fit this grain
- reporting queries should not become permanently hardcoded to Google-only table names
- provider-specific ingestion may still exist under the hood

Suggested v1 strategy:

- keep Google Search Console as the only implemented provider initially
- keep the current Google-specific connection and sync tables as implementation details
- treat `analytics_search_query_facts` as the long-term reporting contract
- avoid coupling new report queries directly to Google-only table names unless the code is clearly isolated

Recommended grain:

- one row per `analytics_site_id + provider + date + query + page + country + device`

Recommended constraints:

- unique index on `(analytics_site_id, provider, date, query, page, country, device)`

Important product rule:

- query-level traffic and revenue from search providers should be treated as aggregated reporting data
- reports may estimate keyword revenue
- raw visits must not be rewritten to pretend they know an exact query per session

Recommended v1 dimension coverage:

- `query`
- `page`
- `country`
- `device`
- provider
- date range

Recommended v1 non-goals:

- exact per-session keyword truth
- live search-provider metrics
- cross-provider blended ranking semantics beyond the normalized fact shape

### Commerce Accounts

Revenue should be optional per analytics site.

Some sites will use:

- no commerce provider at all
- Stripe
- Paddle
- Lemon Squeezy
- Shopify

One important distinction:

- Stripe, Paddle, and Lemon Squeezy are primarily payment/subscription providers
- Shopify is a commerce/storefront platform and is naturally order-oriented

So the architecture should model business outcomes broadly enough to support both payment-centric and order-centric providers.

Recommended control-plane tables:

- `analytics_commerce_accounts`
- `analytics_commerce_site_bindings`

Suggested columns:

- `id`
- `analytics_site_id`
- `provider`
- `status`
- `account_label`
- `credentials`
- `metadata`
- timestamps

Suggested `analytics_commerce_site_bindings` columns:

- `id`
- `analytics_site_id`
- `analytics_commerce_account_id`
- `provider`
- `external_store_identifier`
- `external_store_type`
- `active`
- `last_verified_at`
- `metadata`
- timestamps

Recommended provider values:

- `stripe`
- `paddle`
- `lemonsqueezy`
- `shopify`
- `manual`

Recommended account behavior:

- credentials or tokens must be encrypted
- account rows should be reusable across site bindings
- status should distinguish active, inactive, revoked, and errored states
- provider-specific metadata should stay structured enough for replay and support tooling

Recommended binding behavior:

- bindings map an external storefront, merchant, or billing scope onto one `analytics_site`
- one site may have at most one active binding per provider for its primary reporting flow
- one account may serve many bindings
- bindings should support historical inactive rows
- bindings should be the place where site-specific verification and store/property metadata live

### Customers

Recommended table:

- `analytics_customers`

Suggested columns:

- `id`
- `analytics_site_id`
- `analytics_profile_id`
- `analytics_commerce_account_id`
- `provider`
- `external_customer_id`
- `email`
- `name`
- `metadata`
- timestamps

Why this exists:

- provider webhooks often identify a customer before a browser session
- profile linking may happen after the first payment arrives

Recommended constraints:

- unique provider-customer identity per site for active rows
- later merges should re-point facts to the canonical customer/profile without losing original external identifiers

### Orders

Revenue analytics should not be modeled as payments alone.

Recommended table:

- `analytics_orders`

Suggested columns:

- `id`
- `analytics_site_id`
- `analytics_profile_id`
- `analytics_customer_id`
- `analytics_commerce_account_id`
- `provider`
- `external_id`
- `status`
- `subtotal_amount_cents`
- `tax_amount_cents`
- `discount_amount_cents`
- `total_amount_cents`
- `currency`
- `occurred_at`
- `metadata`
- timestamps

Recommended line item table:

- `analytics_order_line_items`

Suggested columns:

- `id`
- `analytics_site_id`
- `analytics_order_id`
- `external_id`
- `product_id`
- `product_name`
- `variant_id`
- `variant_name`
- `quantity`
- `unit_amount_cents`
- `total_amount_cents`
- `metadata`
- timestamps

Recommended order semantics:

- `analytics_orders` represents the business transaction
- order status should preserve provider semantics closely enough for auditability
- derived metrics like order count should be computed from successful or reportable order states, not from every raw row

Recommended derived metrics from orders:

- orders count
- conversion count
- average order value
- product mix
- top products / plans by source

### Payments

Recommended table:

- `analytics_payments`

Suggested columns:

- `id`
- `analytics_site_id`
- `analytics_profile_id`
- `analytics_order_id`
- `analytics_customer_id`
- `analytics_commerce_account_id`
- `provider`
- `external_id`
- `provider_event_id`
- `kind`
- `status`
- `gross_amount_cents`
- `net_amount_cents`
- `fee_amount_cents`
- `tax_amount_cents`
- `currency`
- `occurred_at`
- `metadata`
- timestamps

Recommended `kind` values:

- `payment`
- `renewal`
- `refund`
- `chargeback`

Recommended payment semantics:

- payments are ledger-like facts, not mutable summary rows
- partial refunds should be separate facts, not destructive updates to the original purchase
- chargebacks should be explicit facts
- renewals should be explicit facts
- one order may have multiple payment facts over time

Recommended constraints:

- unique `external_id` per provider/account where possible
- unique webhook/provider event id when available
- idempotent upsert behavior for repeated provider deliveries

Why keep both orders and payments:

- Shopify and storefront systems are order-oriented
- Stripe, Paddle, and Lemon Squeezy often expose payment and subscription lifecycle separately
- revenue reporting needs business truth, not one provider-specific object model

### Subscriptions

Recommended table:

- `analytics_subscriptions`

Suggested columns:

- `id`
- `analytics_site_id`
- `analytics_profile_id`
- `analytics_customer_id`
- `analytics_commerce_account_id`
- `provider`
- `external_id`
- `plan_id`
- `plan_name`
- `status`
- `started_at`
- `canceled_at`
- `metadata`
- timestamps

Recommended subscription semantics:

- subscriptions track durable commercial relationships
- payments remain the money facts
- subscription status changes should not replace payment facts
- if subscriptions are out of scope initially, they can be deferred, but the order/payment schema should not block adding them later

### Attribution Facts

The system should make attribution explicit instead of hiding it inside ad hoc report joins.

Recommended table:

- `analytics_attribution_facts`

Suggested columns:

- `id`
- `analytics_site_id`
- `subject_type`
- `subject_id`
- `model`
- `dimension_type`
- `dimension_value`
- `credit_ratio`
- `revenue_cents`
- `conversions_count`
- timestamps

Recommended `subject_type` values:

- `order`
- `payment`
- `subscription`

Recommended `model` values:

- `last_touch`
- `first_touch`
- `linear`
- `estimated_search`

Recommended `dimension_type` values:

- `source`
- `referrer`
- `campaign`
- `page`
- `country`
- `device`
- `keyword`

Important distinction:

- source, campaign, landing page, and country/device revenue can often be exact enough
- keyword revenue from Google/Bing search providers should be treated as estimated

Recommended use:

- attribution facts should be derived from behavior and commerce facts, not entered manually
- they should support recomputation when attribution rules change
- they should not be the sole source of truth for revenue amounts

Recommended minimum models to ship first:

- `last_touch`
- `estimated_search`

Why:

- `last_touch` answers the most common traffic allocation question
- `estimated_search` is enough to power keyword revenue without pretending it is exact

## UI Structure

The agreed UI structure is:

- `Live`
- `Reports`
- `Analytics Settings`

Within `Analytics Settings`:

- `Funnels`
- `Goals`
- `Properties`
- `Google Search Console`

Important distinction:

- `Funnels`, `Goals`, and `Properties` are internal analytics definitions
- `Google Search Console` is an external integration tab

Longer term, `Analytics Settings` should grow into:

- analytics definitions
  - `Funnels`
  - `Goals`
  - `Custom Properties`
- external integrations
  - `Search Providers`
  - `Commerce`

For a future SaaS product, this split remains valid:

- analytics definitions stay site-scoped
- integrations are optional per site
- a site may have search integrations, commerce integrations, both, or neither

The current Google Search Console UI is still a valid first step, but future Bing and payment providers should fit under these broader integration buckets.

This is a valid tab layout, but the backend should not collapse all four into one generic settings blob.

Singleton behavior:

- if analytics has exactly one active site, the frontend should behave as if analytics is singular
- the frontend should not need to know about site ids or site selection in this mode
- site switching should only appear when multiple analytics sites exist and the current request cannot resolve one unambiguously

Recommended route contract:

- single-site mode:
  - `/admin/analytics`
  - `/admin/analytics/live`
  - `/admin/settings/analytics`
- multi-site mode:
  - `/admin/analytics/sites/:public_id`
  - `/admin/analytics/sites/:public_id/live`
  - `/admin/settings/analytics?site=:public_id`
- legacy compatibility:
  - `/admin/analytics/reports` should redirect to `/admin/analytics`
  - `/admin/analytics/sites/:public_id/reports` should redirect to `/admin/analytics/sites/:public_id`
  - ambiguous generic analytics routes should redirect to `/admin/settings/analytics`

Reasoning:

- single-site products should get clean singleton URLs that match the current app UX
- multi-site mode still keeps the analytics root explicit in the route
- `public_id` is a cleaner boundary than an internal numeric database id
- site-scoped API routes can remain explicit even when the shell URLs are singleton in single-site mode

## Live vs Reports

### Live

Google Search Console does not belong in live analytics.

Reasons:

- Search Console data is delayed
- Search Console is not request-time event data
- live views should only use active visit/session data

### Reports

Google Search Console belongs in reports, especially in acquisition/source reporting:

- search queries
- clicks
- impressions
- CTR
- average position

Phase 1 scope:

- Google Search Console is reporting-only
- it should not mutate visit attribution
- it should not assign per-visit or per-user organic query data

If later combined reports are useful, they should join GSC facts and visit facts in reporting, not by rewriting raw visit data.

### Commerce in Reports

Commerce data belongs in reports and profile journeys, not in live analytics.

Recommended product questions:

- who purchased
- where purchasers came from
- what landing pages convert
- what campaigns and sources drive revenue
- what countries, devices, and browsers bring paying traffic

Recommended rule:

- orders and payments should appear inside profile journeys
- top-line revenue metrics should be derived from orders/payments facts
- conversion rate, orders count, AOV, and revenue per visitor should be derived report metrics, not primary tables

For the current app, this remains future-facing. The present implementation focus should stay on search/reporting improvements because this site does not currently have a commerce provider.

Recommended commerce metrics:

- orders
- purchasers
- gross revenue
- net revenue
- refunds
- AOV
- revenue per visitor
- conversion rate
- repeat purchase rate

Recommended profile metrics:

- first purchase date
- last purchase date
- lifetime revenue
- orders count
- current subscription state if relevant

### Future Search Terms Preview

A later product enhancement may show a `Search Terms Preview` on profile/session views for Google organic traffic.

That preview should:

- be powered by cached Google Search Console facts
- only appear for Google organic sessions or profiles
- use signals like landing page, date window, country, and device
- present probable queries, not exact per-visit truth

Important constraint:

- this is an inferred preview, not exact attribution
- UI copy should make that clear with language like `preview`, `likely queries`, or `probable search terms`
- raw visit/session facts should not be rewritten with a fake exact `search_query`
- keyword revenue should be labeled as estimated or inferred, not exact

## Query Adapter Strategy

The codebase already has the start of an adapter seam:

- `Analytics::Storage`
- `Analytics::StorageBacked`
- `*::Postgres` query adapters

The correct future direction is:

- `Analytics::*Query::Postgres`
- later `Analytics::*Query::Clickhouse`

But this only applies to the fact-query layer.

It does **not** mean:

- remove Postgres from analytics entirely
- move goals, funnels, OAuth, and configuration into ClickHouse

Correct mental model:

- Postgres remains for control/configuration
- the query adapter for fact data can later be swapped from Postgres to ClickHouse

## Naming and Code Structure

Follow the same broad style used in Fizzy and other Basecamp-style Rails apps:

- one clear root aggregate
- shallow controllers
- specific named models instead of generic service/config blobs
- scope everything through the current root

Important style note from Campfire/Writebook/Fizzy:

- single-root apps keep simple current-context accessors like `Current.account`
- reusable subsystems should not automatically claim that same global namespace
- analytics should therefore use `Analytics::Current`, while the host app keeps `Current`

Recommended naming:

- `Analytics::Current`
- `Analytics::Bootstrap`
- `Analytics::AdminSiteResolver`
- `Analytics::TrackingSiteResolver`
- `Analytics::Paths`
- `Analytics::Site`
- `Analytics::SiteBoundary`
- `Analytics::Goal`
- `Analytics::Funnel`
- `Analytics::AllowedEventProperty`
- `Analytics::GoogleSearchConsoleConnection`
- `Analytics::GoogleSearchConsole::Sync`
- `Analytics::GoogleSearchConsole::SyncJob`
- `Analytics::GoogleSearchConsole::QueryRow`

Controller shape:

- `Admin::Analytics::SitesController`
- `Admin::Analytics::ReportsController`
- `Admin::Analytics::LiveController`
- `Admin::Analytics::SettingsController`
- `Admin::Analytics::GoalsController`
- `Admin::Analytics::FunnelsController`
- `Admin::Analytics::AllowedEventPropertiesController`
- `Admin::Analytics::GoogleSearchConsoleConnectionsController`

`Admin::Analytics::SettingsController` may still render the settings shell page for one site, but writes should stay routed to typed resources rather than one mega payload.

Longer term, settings controllers should not need to inherit all report-query behavior. Keep them thin and scoped through the resolved analytics site.

## Edge Cases To Design For

### Site Ownership and Reuse

- one host app account may own multiple analytics sites
- some host apps are multi-tenant, some are effectively single-account
- analytics must not assume one specific host tenancy model
- owner references should be stored as stable keys, not via cross-database foreign keys
- single-site mode should be backend-owned and invisible to the frontend
- multi-site mode should expose explicit switching in settings instead of silently guessing from admin URLs

### Hostnames

- one site may have `example.com`, `www.example.com`, and additional aliases
- the same host may contain multiple analytics sites under different path prefixes
- hostnames can change over time
- historical data should remain attached to the same `analytics_site`
- `hostname` on visits is useful data but should not be the only ownership boundary
- boundary resolution must be deterministic and explicit
- admin requests must not reuse tracking path resolution rules

### Google Search Console

- a connected Google account may later lose access to a property
- a selected property may be a domain property or URL-prefix property
- Search Console data is delayed and quota-limited
- report pages should not depend on live calls to Google
- connection status and property verification need explicit handling
- Search Console data should be treated as aggregated reporting data, not per-visit attribution data
- any session/profile `Search Terms Preview` must remain probabilistic and clearly labeled as such

### Profiles

- profile records should be scoped by `analytics_site_id`
- identity stitching should not cross sites unless that becomes an explicit product feature later
- historical profile repair should be done explicitly via task or one-off operation, not hidden inside request-time reads
- profile timelines should merge visits, events, orders, and payments, but profiles should not be the only persistence layer for those outcome facts

### Commerce and Payments

- a site may have zero commerce accounts and still use analytics normally
- a site may have more than one commerce provider
- one provider account may serve multiple sites, so account + site binding should remain explicit
- guest checkout must be supported
- delayed webhooks must be able to create facts before profile resolution is complete
- duplicate provider webhook events must be handled idempotently
- refunds and chargebacks should be modeled explicitly, not by mutating original purchase truth
- currency handling should preserve original currency amounts even if reporting later converts them
- subscription renewals should be first-class payment facts, not hidden inside one purchase event
- provider privacy/data-deletion hooks must be part of the design for platforms like Shopify
- some providers retain event history differently, so webhooks should be treated as the durable ingestion source where applicable

### Search Providers

- Google Search Console is the first provider, not the last
- Bing Webmaster should fit the same normalized reporting shape
- provider-specific sync tables are acceptable initially, but reporting should evolve toward normalized search query facts
- keyword, page, country, and device reporting should not assume one provider forever

Recommended provider rollout:

1. Google Search Console first
2. normalize the reporting contract before adding Bing
3. keep Bing as a later provider addition, not a schema redesign

Recommended v1 search reports:

- query performance
- page performance
- country performance
- device performance
- source-level Google organic drilldowns
- profile/session `Search Terms Preview` as inferred, not exact

### Privacy and Compliance

- customer-identifying data should be stored only where it materially improves attribution or profile UX
- sensitive provider credentials must use encryption at rest
- privacy-driven deletions or redactions from providers should be handled explicitly
- profile resolution should prefer stable ids and hashed identifiers over unnecessary raw PII when possible

### First-Run Concurrency

- default-site bootstrap should be idempotent under concurrent first requests
- the first-run path should use a database lock or equivalent guard
- explicit site resolution should only return active sites unless archived-site access is a deliberate feature

### Host Configuration Surface

The host app should configure analytics through one small initializer surface:

- `config.analytics.mode`
- `config.analytics.default_site.host`
- `config.analytics.default_site.name`
- `config.analytics.google_search_console.client_id`
- `config.analytics.google_search_console.client_secret`
- `config.analytics.google_search_console.callback_path`

Recommended defaults:

- single-site apps default to `:single_site`
- Google Search Console callback defaults to
  `/admin/settings/analytics/google_search_console/callback`
- multi-site apps should not define sites in config; sites and boundaries belong in the database

### Google Search Console OAuth Routing

The callback route should be global and stable, not site-scoped.

Preferred shape:

- connect:
  `/admin/analytics/sites/:site/google_search_console/connect`
- callback:
  `/admin/settings/analytics/google_search_console/callback`

The site context should be carried in OAuth `state` and/or session, not in the
callback path itself.

Why:

- simpler Google Cloud redirect configuration
- cleaner single-site UX
- still supports multi-site connections

### Host Config Surface

The host app should configure analytics through a single public API:

```ruby
Analytics.setup do |config|
  config.mode = :single_site
  config.default_site.host = "localhost"
  config.default_site.name = "contextqmd.com"
  config.google_search_console.client_id = ENV["GOOGLE_SEARCH_CONSOLE_CLIENT_ID"]
  config.google_search_console.client_secret = ENV["GOOGLE_SEARCH_CONSOLE_CLIENT_SECRET"]
end
```

Design rules:

1. `Analytics` is the public boundary
   The host app should not need a separate `ahoy.rb` initializer or direct
   `Rails.configuration.x.analytics` access.

2. Ahoy stays internal
   `lib/analytics.rb` installs Ahoy integration, store wiring, and controller
   hooks. The host app should only think in terms of analytics.

3. Config defaults live in analytics-owned code
   The initializer should stay short and host-friendly, with only project-level
   overrides and credentials.

3. Remove legacy fallback booleans
   `gsc_configured?` in
   `app/controllers/concerns/admin/analytics/google_search_console_context.rb`
   still falls back to `x.analytics.gsc_configured` and
   `ENV["ANALYTICS_GSC_CONFIGURED"]`.

   Long term:
   - provider readiness should come from provider credentials + connection rows
   - not from ad hoc booleans

4. Keep provider config symmetrical
   Future Bing config should mirror Google shape:
   - `config.analytics.bing_webmaster.enabled`
   - `config.analytics.bing_webmaster.auth_mode`
   - `config.analytics.bing_webmaster.client_id`
   - `config.analytics.bing_webmaster.client_secret`
   - `config.analytics.bing_webmaster.api_key`
   - `config.analytics.bing_webmaster.callback_path`

5. Expose config diagnostics in settings
   The settings page should eventually show a small diagnostics block for each
   provider:
   - credentials configured or missing
   - callback URL
   - current auth mode
   - last sync status

### Future ClickHouse

- config/integration records should remain in Postgres
- fact queries should not require cross-store joins
- site/config resolution should happen in Postgres first
- the fact adapter should receive resolved site/config inputs and then query the fact store
- denormalized site ownership on both visits and events should exist before any move to ClickHouse

## Non-Goals

This plan does **not** assume:

- moving the entire analytics system to ClickHouse
- replacing all Active Record models with storage-neutral abstractions
- making every analytics table portable to every SQL engine

The goal is cleaner boundaries, not fake portability.

## Recommended Implementation Phases

## Recommended Product Strategy

Do not build every hypothetical provider or product surface at once.

Recommended strategy:

1. build the architecture broadly
2. ship the current app's real integrations well
3. add new providers in vertical slices
4. validate abstractions with real use before widening them further
5. extract to an internal engine before trying to publish a reusable gem

This avoids two common mistakes:

- overfitting analytics to the current app only
- overbuilding speculative provider/product code that no site actually uses yet

Recommended near-term product focus for this app:

- keep the current app optimized for single-site mode
- keep Google Search Console as the primary external integration
- improve search reporting and SEO-oriented profile enrichment
- keep commerce architecture documented and ready, but do not force current app UX around unused commerce flows

Recommended provider delivery strategy:

- one provider slice at a time
- one clear reporting surface at a time
- one clean operator setup flow at a time

Examples:

- Google Search Console first
- Bing later against the same normalized reporting contract
- one commerce provider or manual ingestion path first when a real site needs it

### Phase 1: Introduce Site Scope

1. Add `analytics_sites`
2. Add `analytics_site_boundaries`
3. Add `analytics_site_id` and `analytics_site_boundary_id` to visits and events
4. Add `analytics_site_id` to other core analytics tables
5. Backfill historical rows using explicit host/path boundary mapping, not a blind single default site unless the dataset is truly single-site
6. Add `Analytics::Current` as the analytics-owned runtime context
7. Add `Analytics::Bootstrap`
8. Add `Analytics::AdminSiteResolver` and `Analytics::TrackingSiteResolver`
9. Add `Analytics::Paths` so route structure is centralized

### Phase 2: Scope Query Execution

1. Refactor report entrypoints so all analytics queries require a site
2. Stop starting queries from `Ahoy::Visit.all`
3. Ensure every report and live endpoint resolves an `Analytics::Site` first
4. Define and centralize deterministic ingestion-time boundary resolution
5. Remove analytics-specific state from the host app's global `Current`
6. Keep generic non-site admin analytics routes singleton-safe only; multi-site flows should use explicit site routes

### Phase 3: Replace Global Definitions

1. Scope goals by site
2. Scope funnels by site
3. Replace global property config with site-scoped allowed event properties
4. Reduce reliance on generic `analytics_settings`

### Phase 4: Google Search Console Integration

1. Add encrypted connection model
2. Add property selection flow
3. Add sync metadata
4. Add cached Search Console fact rows
5. Replace the current placeholder search-terms logic with real synced data
6. Keep GSC integration reporting-only in this phase

### Phase 4.25: Search Reporting Hardening

1. Keep Google-specific ingestion isolated
2. Define normalized search fact readers even if backed by Google-specific storage at first
3. Expand reports around query/page/country/device without pretending per-visit keyword truth
4. Keep search-term preview clearly inferred

This is the current app's highest-value product slice because it already uses Google Search Console and does not yet use commerce providers.

### Phase 4.5: Search Terms Preview Enrichment

1. Add a backend helper that derives likely queries for a Google organic session/profile from cached GSC facts
2. Scope matching by landing page, date window, country, and device where available
3. Return ranked probable queries with weights or percentages
4. Keep the feature read-only and explicitly probabilistic

### Phase 5: Commerce Outcome Layer

1. Add commerce accounts
2. Add commerce site bindings
3. Add customers
4. Add orders and order line items
5. Add payments
6. Add subscriptions where relevant
7. Show orders and payments in profile journeys
8. Keep the current site able to have zero commerce integrations

### Phase 6: Attribution Layer

1. Add explicit attribution facts
2. Start with `last_touch` and `first_touch`
3. Add `estimated_search` for keyword-level revenue attribution
4. Keep estimated keyword revenue clearly labeled in product UI

### Phase 7: Provider-Neutral Search Reporting

1. Introduce normalized search provider accounts and bindings
2. Add provider-neutral search query facts
3. Keep Google-specific ingestion as a first implementation detail if needed
4. Add Bing later without forcing report query rewrites
5. Keep provider-specific ranking semantics isolated at ingest time, not spread through report queries

### Phase 7.5: Commerce Provider Expansion

1. Start with one provider or manual ingestion path
2. Keep provider-neutral commerce tables from day one
3. Add provider-specific webhook/API ingestion adapters behind that model
4. Support Stripe-like payment providers and Shopify-like order platforms without schema redesign

Do not implement every provider at once. Validate the model with one real provider or one manual ingestion path first.
### Phase 8: Fact-Store Optionality

1. Keep the current `Postgres` query adapters working
2. Add `Clickhouse` adapters later for the high-volume fact-query classes
3. Keep Postgres as the control plane

### Operations

Historical cleanup and repair should be explicit operational work, not runtime application behavior.

Recommended pattern:

- schema evolution via migrations
- historical data repair via rake task or one-off script
- no request-time repair for analytics site ownership

## Current Placeholder To Replace Later

The current search terms implementation is a placeholder:

- it derives terms from Google referrer URLs
- it fabricates impressions, CTR, and position

That should be removed once Google Search Console integration is implemented properly.

## Summary

The main design decision is simple:

- do not bolt Google Search Console onto the current global analytics schema
- first introduce `Analytics::Site` as the root scope
- treat search providers and commerce providers as site-scoped integrations
- keep identity, behavior, search, commerce, and attribution as distinct layers
- keep Postgres as the control/config plane
- keep the fact-query layer adapter-backed so it can move to ClickHouse later

This provides a clean foundation for:

- reusable analytics across projects
- site-scoped goals/funnels/properties
- proper Google Search Console integration
- future Bing and other search providers
- future Stripe, Paddle, Lemon Squeezy, and Shopify integrations
- future revenue and attribution reporting
- future storage evolution without rewriting the whole analytics system
