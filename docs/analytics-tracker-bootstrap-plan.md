# Analytics Tracker Bootstrap Plan

This document defines the recommended long-term bootstrap contract for the analytics tracker.

It is intentionally narrow:

- exact browser bootstrap payload
- exact public snippet contract
- optional internal site attestation shape
- first-party vs external snippet delivery modes
- server-side validation rules
- rollout order

It does not replace the broader analytics architecture plan. It refines the tracking/bootstrap boundary only.

## Goals

1. Keep analytics scope server-owned.
2. Support both first-party app pages and third-party embeddable installs.
3. Prevent public clients from arbitrarily claiming any analytics site.
4. Preserve single-site simplicity while allowing multi-site extraction later.
5. Keep the runtime tracker framework-agnostic.

## Non-Goals

- Full public analytics API design
- Full ingestion schema redesign
- ClickHouse adapter design

## Core Rule

The browser must not be the source of truth for analytics site ownership.

The browser may carry a short public `website_id`.
The server may additionally issue an internal, signed site attestation token.
The server still validates tracked host/path/url and resolves boundary ownership.

Long-term, first-party and external installs should use the same trust model:

- both receive a unified bootstrap payload
- both may carry the same internal attestation shape at runtime
- neither mode may rely on raw browser-provided ids or domains as authority

## Delivery Modes

### 1. First-Party Bootstrap

Used for pages rendered by this Rails app.

Recommended shape:

```html
<script>
  window.analyticsConfig = { ...server_bootstrap_payload... }
</script>
<script defer src="/assets/analytics.js"></script>
```

Properties:

- bootstrap is emitted by Rails layout/helper
- bootstrap is trusted because it is server-rendered
- no copy-paste setup required
- single-site mode stays effectively invisible to the frontend

### 2. External Snippet Bootstrap

Used for third-party sites embedding the tracker.

Recommended shape:

```html
<script
  defer
  src="https://datafa.st/analytics/script.js"
  data-website-id="site_xxx"
></script>
```

Properties:

- `data-website-id` is the public lookup key
- `/analytics/script.js` is a tiny public loader that normalizes the public identifier into `window.analyticsConfig` and then imports the real tracker bundle

Do not treat a raw `data-website-id` as authoritative proof of site ownership.
It is an identifier, not the trust boundary.

## Unified Bootstrap Payload

Both delivery modes should normalize into the same runtime config object before tracker initialization.

Suggested shape:

```json
{
  "version": 1,
  "transport": {
    "eventsEndpoint": "/analytics/events"
  },
  "site": {
    "websiteId": "site_xxx",
    "token": "signed_internal_site_token",
    "domainHint": "example.com"
  },
  "tracking": {
    "hashBasedRouting": false,
    "initialPageviewTracked": true,
    "initialPageKey": "/docs?tab=intro"
  },
  "filters": {
    "includePaths": [],
    "excludePaths": ["/admin", "/analytics", "/ahoy", "/cable"],
    "excludeAssets": [".png", ".jpg", ".css", ".js"]
  },
  "debug": false
}
```

### Field Rules

- `version`
  - required
  - allows future bootstrap contract changes
- `transport.eventsEndpoint`
  - required
  - must be explicit so the same tracker can work first-party and cross-origin
- `site.websiteId`
  - public identifier for the tracked site
  - safe to expose in copy-paste snippets
  - must still be resolved and validated server-side
- `site.token`
  - internal runtime attestation only
  - may be omitted during migration
  - must not be the primary public snippet contract
- `site.domainHint`
  - optional
  - useful for snippet UX, debugging, and sanity checks
  - not authoritative for ownership
- `tracking.initialPageviewTracked`
  - first-party only
  - omitted or `false` for external installs
- `tracking.initialPageKey`
  - only meaningful when the server already counted the initial pageview
- `filters.*`
  - backend-owned effective rules
  - frontend tracker uses them only as an early guardrail
  - must not replace server-side validation

User config rule:

- internal/system excludes are analytics-owned defaults
- those defaults should come from one analytics-owned source in code, then be
  merged into the effective tracker filters during bootstrap
- user-defined include/exclude rules should be configured once in analytics
  settings and stored in a typed `analytics_site_tracking_rules` record
- bootstrap should deliver the effective merged rules to the tracker
- users should never manage separate frontend and backend exclude lists

## Internal Site Attestation Token

The token should be opaque to the browser, signed by the server, and treated as
an internal runtime detail rather than a copy-paste HTML contract.

Recommended payload before signing:

```json
{
  "v": 1,
  "site_public_id": "site_123",
  "allowed_boundaries": [
    { "host": "example.com", "path_prefix": "/" },
    { "host": "www.example.com", "path_prefix": "/blog" }
  ],
  "allowed_hosts": ["example.com", "www.example.com"],
  "allowed_path_prefixes": ["/", "/blog"],
  "environment": "production",
  "issued_at": 1760000000,
  "expires_at": 1762592000,
  "mode": "first_party"
}
```

### Signing Rules

- sign with `Rails.application.message_verifier(...)` or equivalent
- token must be tamper-evident
- token must expire
- token version must be embedded in the payload
- host/path/environment claims must be normalized before signing

### Token Semantics

- `site_public_id` identifies the intended analytics site
- `allowed_boundaries` is the authoritative constraint and preserves valid host/path pairs
- `allowed_hosts` and `allowed_path_prefixes` are derived/debugging claims, not the primary matcher
- `environment` prevents accidental cross-environment reuse
- token does not replace boundary resolution
- token is a trusted explicit claim, not a blind override

## Ingestion Validation Rules

On bootstrap:

1. normalize the incoming URL, host, and path
2. resolve boundary ownership through `Analytics::TrackingSiteResolver`
3. resolve the public `website_id` server-side
4. compare explicit site identity vs resolved boundary site
5. mint a short-lived internal site token only when the claim is valid

On event ingestion:

1. normalize the incoming URL, host, and path
2. resolve boundary ownership through `Analytics::TrackingSiteResolver`
3. verify the internal attestation token
4. compare token site vs resolved boundary site

Recommended behavior:

- bootstrap `website_id`, no boundary conflict:
  - accept resolved site and mint token
- bootstrap `website_id`, boundary resolves to a different site:
  - hard reject and log
- valid attestation token, no boundary conflict:
  - accept token site
- valid attestation token, boundary resolves to a different site:
  - hard reject and log
- invalid token:
  - reject and log

Recommended comparison rules:

- if `allowed_boundaries` is present, the normalized request host/path must match one allowed boundary pair
- if `environment` is present, the receiving environment must match it
- if any token constraint fails, reject and log
- if token constraints pass but boundary resolution yields a different site, reject and log

## Public Loader and CORS

External installs need two public capabilities:

- `GET /analytics/script.js`
  - no auth
  - no CSRF
  - safe to embed cross-origin
  - loads the real tracker bundle from the analytics service origin
- `POST /analytics/bootstrap`
  - validates the external embed against host/path ownership
  - returns effective runtime config plus a short-lived site token
- `OPTIONS /analytics/bootstrap`
  - returns permissive tracker CORS headers
- `OPTIONS /analytics/events`
  - returns permissive tracker CORS headers
  - allows cross-origin `application/json` event posts from the snippet

`POST /analytics/events` responses should return the same tracker CORS headers.

Internal boundary rule:

- `Analytics` owns the public HTTP surface
- `Ahoy` stays the internal engine handling event creation and visit lifecycle
- public docs and snippets should use `/analytics/events`

## Trust Model

The following must not be trusted as site ownership claims on their own:

- raw `data-website-id`
- browser-provided site ids

The following may be trusted:

- internal signed site attestation token
- server-side lookup of `website_id`, but only during bootstrap and only after normal boundary validation

Server-rendered first-party bootstrap is trusted as a transport for delivering the
internal token.
It is not a separate long-term trust model.

## Runtime Tracker Responsibilities

The tracker should:

- collect page URL, pathname, referrer, title, screen size
- handle SPA navigation and engagement consistently
- read bootstrap from either:
  - `window.analyticsConfig`, or
  - `data-*` attributes on its script element
- normalize both into one internal config object
- expose one public event API for host pages, for example:
  - `window.analytics("signup")`
  - `window.analytics("signup", { plan: "pro" })`
- optionally support declarative goal tracking on DOM nodes, for example:
  - `data-analytics-goal="signup"`
  - `data-analytics-prop-plan="pro"`

The tracker should not:

- decide analytics ownership from raw domain alone
- decide analytics ownership from raw `website_id` alone
- silently invent site scope
- contain product-specific tenant resolution logic
- treat revenue or purchases as generic custom goals

## Recommended Server API Surface

Introduce one server-side bootstrap builder, for example:

```ruby
Analytics::TrackerBootstrap.build(
  request: request,
  initial_pageview_tracked: true,
  initial_page_key: "/"
)
```

It should return the unified payload described above.

Recommended helper outputs:

- first-party inline bootstrap helper for Rails layout
- external snippet helper or admin-generated snippet for copy-paste installs
- declarative HTML goal helper built on the same runtime tracker

## Rollout Plan

### Phase 1

- formalize the unified bootstrap payload
- keep current first-party inline bootstrap
- add `site.websiteId` to the public snippet/runtime config
- keep any signed token internal to the runtime/bootstrap layer

### Phase 2

- add internal site attestation verification on ingest
- add snippet generator in admin settings
- support external snippet installs

### Phase 3

- move explicit site overrides behind `website_id` lookup plus internal attestation
- migrate first-party bootstrap to emit the same public/publicly-documentable
  contract as external mode
- remove any remaining raw site-ownership inputs from the public tracker contract

## Best-Possible End State

The best end state is:

- one runtime tracker
- one bootstrap payload shape
- one public `website_id` contract
- one optional internal attestation token shape
- one ingestion trust model
- server-owned boundary resolution on every request
- hard rejection on token/boundary mismatch

In that end state:

- first-party pages are simpler only in delivery, not in trust semantics
- external snippet installs are safe by default
- single-site mode remains invisible to the frontend
- multi-site support does not require rethinking the tracker contract
- remove any legacy raw site-id ownership claims from public tracking requests

## Recommended End State

- one runtime tracker
- one unified bootstrap payload
- one server bootstrap builder
- short public `website_id` for snippet installs
- internal attestation tokens for trusted explicit site identity
- server-owned boundary resolution

That gives:

- simple first-party setup
- safe external snippet support
- compatibility with single-site mode
- clean migration path to multi-site analytics
