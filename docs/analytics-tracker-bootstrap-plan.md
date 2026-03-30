# Analytics Tracker Bootstrap Plan

This document defines the recommended long-term bootstrap contract for the analytics tracker.

It is intentionally narrow:

- exact browser bootstrap payload
- exact signed site token shape
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

The browser may carry a server-issued, signed site token.
The server still validates tracked host/path/url and resolves boundary ownership.

Long-term, first-party and external installs should use the same trust model:

- both receive a unified bootstrap payload
- both may carry the same signed site token shape
- neither mode may rely on raw browser-provided site ids or domains as authority

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
  src="https://datafa.st/js/script.js"
  data-site-token="signed_site_token"
  data-domain="example.com"
  data-api="https://datafa.st/a/events"
></script>
```

Properties:

- `data-site-token` is authoritative
- `data-domain` is advisory only
- `data-api` is explicit and environment-safe
- `/js/script.js` is a tiny public loader that normalizes `data-*` attributes into `window.analyticsConfig` and then imports the real tracker bundle

Do not treat a raw `data-website-id` as authoritative.

## Unified Bootstrap Payload

Both delivery modes should normalize into the same runtime config object before tracker initialization.

Suggested shape:

```json
{
  "version": 1,
  "transport": {
    "eventsEndpoint": "/ahoy/events"
  },
  "site": {
    "token": "signed_site_token",
    "domainHint": "example.com"
  },
  "tracking": {
    "hashBasedRouting": false,
    "initialPageviewTracked": true,
    "initialPageKey": "/docs?tab=intro"
  },
  "filters": {
    "includePaths": [],
    "excludePaths": ["/admin", "/ahoy", "/cable"],
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
- `site.token`
  - optional only during migration from the current first-party bootstrap
  - required in the long-term end state for both first-party and external modes
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
  - tracker-side guardrails only
  - must not replace server-side validation

## Signed Site Token

The token should be opaque to the browser and signed by the server.

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

On every tracked request:

1. normalize the incoming URL, host, and path
2. resolve boundary ownership through `Analytics::TrackingSiteResolver`
3. verify the signed site token if present
4. compare token site vs resolved boundary site

Recommended behavior:

- no token, single active site:
  - accept and use the singleton site
- no token, multi-site, boundary resolves uniquely:
  - accept and use resolved boundary site
- no token, multi-site, boundary unresolved:
  - drop or route to unresolved bucket
- valid token, no boundary conflict:
  - accept token site
- valid token, boundary resolves to a different site:
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

- `GET /js/script.js`
  - no auth
  - no CSRF
  - safe to embed cross-origin
  - loads the real tracker bundle from the analytics service origin
- `OPTIONS /ahoy/events`
  - returns permissive tracker CORS headers
  - allows cross-origin `application/json` event posts from the snippet

`POST /ahoy/events` responses should return the same tracker CORS headers.

## Trust Model

The following must not be trusted as site ownership claims on their own:

- raw `data-domain`
- raw `data-website-id`
- browser-provided site ids

The following may be trusted:

- signed site token

Server-rendered first-party bootstrap is trusted as a transport for delivering the signed token.
It is not a separate long-term trust model.

## Runtime Tracker Responsibilities

The tracker should:

- collect page URL, pathname, referrer, title, screen size
- handle SPA navigation and engagement consistently
- read bootstrap from either:
  - `window.analyticsConfig`, or
  - `data-*` attributes on its script element
- normalize both into one internal config object

The tracker should not:

- decide analytics ownership from raw domain alone
- silently invent site scope
- contain product-specific tenant resolution logic

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

## Rollout Plan

### Phase 1

- formalize the unified bootstrap payload
- keep current first-party inline bootstrap
- add `site.token` support in tracker runtime

### Phase 2

- add signed site token verification on ingest
- add snippet generator in admin settings
- support external snippet installs

### Phase 3

- require signed token for explicit site overrides
- migrate first-party bootstrap to emit the same site token contract as external mode
- remove any remaining raw site-ownership inputs from the public tracker contract

## Best-Possible End State

The best end state is:

- one runtime tracker
- one bootstrap payload shape
- one signed site token shape
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
- signed site tokens for trusted explicit site identity
- server-owned boundary resolution

That gives:

- simple first-party setup
- safe external snippet support
- compatibility with single-site mode
- clean migration path to multi-site analytics
