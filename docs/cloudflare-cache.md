# Cloudflare Cache For Public Library Pages

This app serves the same route in two forms:

- full HTML document requests
- Inertia navigation requests (`X-Inertia: true`)

Those responses must not be treated the same at the CDN layer.

## Origin behavior

For `GET /libraries/:slug/versions/:version/pages/*page_uid`:

- Anonymous full HTML requests return:
  - `Cache-Control: public, max-age=3600`
  - `Cloudflare-CDN-Cache-Control: public, max-age=3600, stale-while-revalidate=60`
  - `ETag` / `Last-Modified`
- Inertia requests return:
  - `Cache-Control: no-store`
- Authenticated full HTML requests return:
  - `Cache-Control: private, no-store`

This is intentional because the shared Inertia shell can include personalized header/nav state via `current_user`, `current_identity`, flash, cookies, or session data.

## Required Cloudflare rules

Use ordered Cache Rules so bypass happens before cache eligibility.

### Rule 1: Bypass personalized or Inertia traffic

Action:

- `Bypass cache`

Match:

- Request method is `GET`
- URI path matches `/libraries/*/versions/*/pages/*`
- and one of:
  - request header `X-Inertia` exists
  - request has auth/session cookies

Use the real cookie names from production. At minimum, include the Rails session cookie and any remember-me/auth cookies.

### Rule 2: Cache anonymous HTML library pages

Action:

- `Eligible for cache`
- Edge TTL: `Use cache-control header if present, bypass cache if not`
- Browser TTL: `Respect origin`

Match:

- Request method is `GET`
- URI path matches `/libraries/*/versions/*/pages/*`
- request header `X-Inertia` does not exist
- request does not have auth/session cookies

## Why both origin headers and Cloudflare rules are needed

Origin headers alone are not enough because Cloudflare can serve a cached response before the request reaches Rails.

The bypass rule is what prevents Cloudflare from serving an anonymous cached HTML page to a signed-in user or to an Inertia JSON navigation request.

## Verification

Anonymous full-page request:

- expect `CF-Cache-Status: MISS`, then `HIT`
- expect `Cache-Control: public, max-age=3600`
- expect `Cloudflare-CDN-Cache-Control: public, max-age=3600, stale-while-revalidate=60`

Inertia request:

- expect `X-Inertia: true`
- expect `Cache-Control: no-store`
- expect cache bypass

Authenticated full-page request:

- expect personalized nav/header
- expect `Cache-Control: private, no-store`
- expect cache bypass
