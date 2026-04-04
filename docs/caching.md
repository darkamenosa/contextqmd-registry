# Caching

This app uses three separate caching layers:

1. Inertia client prefetch cache
2. HTTP conditional caching (`ETag` / `Last-Modified` -> `304 Not Modified`)
3. Server-side `Rails.cache`

They solve different problems. Do not treat them as interchangeable.

## What Each Layer Does

### Inertia Prefetch Cache

Frontend links can prefetch the next page's Inertia response into browser memory.

- First prefetch request is usually `200`, not `304`
- Helps next-click navigation feel faster
- Does not persist like browser HTTP cache
- Does not replace backend `fresh_when`

Current frontend prefetch helpers:

- [app-shell-prefetch.ts](/Users/tuyenhx/Workspace/experiments/contextqmd_2/contextqmd-registry/app/frontend/lib/app-shell-prefetch.ts)
- [admin-shell-prefetch.ts](/Users/tuyenhx/Workspace/experiments/contextqmd_2/contextqmd-registry/app/frontend/lib/admin-shell-prefetch.ts)
- [public-shell-prefetch.ts](/Users/tuyenhx/Workspace/experiments/contextqmd_2/contextqmd-registry/app/frontend/lib/public-shell-prefetch.ts)
- [shell-prefetch.ts](/Users/tuyenhx/Workspace/experiments/contextqmd_2/contextqmd-registry/app/frontend/lib/shell-prefetch.ts)

### Inertia Transport Note

For this app's installed client (`@inertiajs/react` `3.0.0` / `@inertiajs/core` in `node_modules`), normal Inertia requests use the built-in `XMLHttpRequest` client by default.

Important details:

- the installed package initializes `httpClient = new XhrHttpClient()`
- that client reads the `XSRF-TOKEN` cookie and sends `X-XSRF-TOKEN`
- `axiosAdapter` is still exported, but optional
- `axios` is not currently installed in this app's `node_modules`

So in this repo today:

- Inertia page visits and prefetches are using the built-in XHR transport
- some custom endpoints still use plain `fetch`
- Axios is relevant as optional Inertia adapter/history, but not the default transport we are relying on

### HTTP Conditional Caching

This is the `304` path.

- Browser first gets a normal `200` response with validators
- Later browser reload/revisit sends `If-None-Match` / `If-Modified-Since`
- Rails can return `304` with no body
- This helps refreshes and revisits, not the first request

### Rails.cache

This avoids recomputing expensive props on the server.

- Helps even when the browser has no prior cached response
- Usually paired with `fresh_when`, not used instead of it
- Best for expensive dashboards or public list payloads

## Important Browser Reality

A first prefetch is usually `200`.

That is expected.

`304` only appears when:

- the browser already has a cached copy of that exact variant
- the request sends validators
- the server responds with matching validators
- the response is not being destabilized by cookie/session rewrites

## HTML vs Inertia Variant Split

The same URL can return:

- full HTML document
- Inertia JSON (`X-Inertia: true`)

These must never share one validator.

Current rule everywhere we use conditional caching:

```ruby
etag: [request.inertia? ? "inertia" : "html", ...]
```

And always:

```ruby
merge_vary_header!("X-Inertia")
```

## Flash Rule

If a response carries flash, do not allow `304`.

Reason:

- a `304` reuses the old browser body
- if that old body contained flash, stale flash can reappear

Current rule:

```ruby
if flash.to_hash.present?
  response.headers["Cache-Control"] = "no-store"
else
  fresh_when(...)
end
```

## Session / XSRF Gotcha

The hardest bug we hit was: controller-side `fresh_when` looked correct, but browsers still did not revalidate.

Root causes:

1. `inertia_rails` writes `XSRF-TOKEN` on every request by default
2. cookie-backed session responses can rewrite session cookies on cacheable authenticated GETs

That breaks clean browser revalidation in practice.

Current fix:

- [config/initializers/inertia_xsrf_cookie.rb](/Users/tuyenhx/Workspace/experiments/contextqmd_2/contextqmd-registry/config/initializers/inertia_xsrf_cookie.rb)
  - overrides the gem's anonymous after_action
  - only writes `XSRF-TOKEN` when needed
- cacheable private GET pages explicitly set:

```ruby
request.session_options[:skip] = true if request.get? || request.head?
```

Do not move that back into a generic concern unless there is a very strong reason.

It is intentionally explicit in each private cached controller.

### Why The XSRF Override Exists

`inertia_rails` writes the `XSRF-TOKEN` cookie on every request by default.

That is convenient, but in this app it prevented clean browser revalidation for cacheable GET pages because the response kept changing at the cookie/header layer even when the page data was unchanged.

So we override that behavior in [config/initializers/inertia_xsrf_cookie.rb](/Users/tuyenhx/Workspace/experiments/contextqmd_2/contextqmd-registry/config/initializers/inertia_xsrf_cookie.rb):

- remove the gem's unconditional cookie writer
- replace it with a stricter rule:
  - if request is `GET`/`HEAD` and `XSRF-TOKEN` cookie already exists, do nothing
  - otherwise write `XSRF-TOKEN = form_authenticity_token`

### Security Notes For The XSRF Override

This change should not weaken CSRF protection.

Why:

- Rails still verifies CSRF on non-GET requests against the session token
- Rails accepts the token from the form param or the `X-CSRF-Token` / `X-XSRF-TOKEN` header
- our layout still emits [csrf_meta_tags](/Users/tuyenhx/Workspace/experiments/contextqmd_2/contextqmd-registry/app/views/layouts/application.html.erb)
- some frontend code also reads the meta tag directly via [csrf-token.ts](/Users/tuyenhx/Workspace/experiments/contextqmd_2/contextqmd-registry/app/frontend/lib/csrf-token.ts)

For this app specifically:

- default Inertia requests use the built-in XHR client
- that client reads `XSRF-TOKEN` and sends `X-XSRF-TOKEN`
- some non-Inertia code uses `fetch` and reads the meta tag instead

Practical effect:

- the override mainly reduces unnecessary cookie churn on steady-state GETs
- if the browser ever has a stale XSRF cookie, the likely failure mode is a rejected legitimate POST (`InvalidAuthenticityToken`), not silent CSRF bypass

### Real Downside / Risk

The main downside is compatibility, not security.

Potential edge case:

- if some flow rotates the session/CSRF token on a `GET` request while an old `XSRF-TOKEN` cookie is already present, our override will not refresh that cookie on that GET
- that can make the next JS mutation fail CSRF verification until a later response refreshes the token

In this app that tradeoff is acceptable because:

- login/logout/registration flows are non-GET and therefore still refresh the cookie
- the initial HTML document includes CSRF meta tags
- we explicitly tested the revalidation path that was previously broken

If the app later introduces session rotation on ordinary GET requests, revisit this override.

## Current Backend `304` Routes

### Private App

- [app/dashboards_controller.rb](/Users/tuyenhx/Workspace/experiments/contextqmd_2/contextqmd-registry/app/controllers/app/dashboards_controller.rb)
- [app/settings_controller.rb](/Users/tuyenhx/Workspace/experiments/contextqmd_2/contextqmd-registry/app/controllers/app/settings_controller.rb)

### Private Admin

- [admin/dashboards_controller.rb](/Users/tuyenhx/Workspace/experiments/contextqmd_2/contextqmd-registry/app/controllers/admin/dashboards_controller.rb)
- [admin/users_controller.rb](/Users/tuyenhx/Workspace/experiments/contextqmd_2/contextqmd-registry/app/controllers/admin/users_controller.rb)
- [admin/libraries_controller.rb](/Users/tuyenhx/Workspace/experiments/contextqmd_2/contextqmd-registry/app/controllers/admin/libraries_controller.rb)
- [admin/crawl_requests_controller.rb](/Users/tuyenhx/Workspace/experiments/contextqmd_2/contextqmd-registry/app/controllers/admin/crawl_requests_controller.rb)

### Public

- [pages_controller.rb](/Users/tuyenhx/Workspace/experiments/contextqmd_2/contextqmd-registry/app/controllers/pages_controller.rb)
- [homepages_controller.rb](/Users/tuyenhx/Workspace/experiments/contextqmd_2/contextqmd-registry/app/controllers/homepages_controller.rb)
- [libraries_controller.rb](/Users/tuyenhx/Workspace/experiments/contextqmd_2/contextqmd-registry/app/controllers/libraries_controller.rb)
- [rankings_controller.rb](/Users/tuyenhx/Workspace/experiments/contextqmd_2/contextqmd-registry/app/controllers/rankings_controller.rb)
- [crawl_requests_controller.rb](/Users/tuyenhx/Workspace/experiments/contextqmd_2/contextqmd-registry/app/controllers/crawl_requests_controller.rb)
- [libraries/pages_controller.rb](/Users/tuyenhx/Workspace/experiments/contextqmd_2/contextqmd-registry/app/controllers/libraries/pages_controller.rb)

## Current `Rails.cache` Usage Worth Knowing

- Dashboard payload:
  - [app/dashboards_controller.rb](/Users/tuyenhx/Workspace/experiments/contextqmd_2/contextqmd-registry/app/controllers/app/dashboards_controller.rb)
- Public list/detail payloads:
  - [homepages_controller.rb](/Users/tuyenhx/Workspace/experiments/contextqmd_2/contextqmd-registry/app/controllers/homepages_controller.rb)
  - [libraries_controller.rb](/Users/tuyenhx/Workspace/experiments/contextqmd_2/contextqmd-registry/app/controllers/libraries_controller.rb)
  - [rankings_controller.rb](/Users/tuyenhx/Workspace/experiments/contextqmd_2/contextqmd-registry/app/controllers/rankings_controller.rb)
  - [libraries/pages_controller.rb](/Users/tuyenhx/Workspace/experiments/contextqmd_2/contextqmd-registry/app/controllers/libraries/pages_controller.rb)

## Pattern For Adding A New Cached Inertia Page

Use controller-local logic. Keep it obvious.

```ruby
merge_vary_header!("X-Inertia")

if flash.to_hash.present?
  response.headers["Cache-Control"] = "no-store"
else
  request.session_options[:skip] = true if request.get? || request.head?

  fresh_when(
    etag: [request.inertia? ? "inertia" : "html", ...route_specific_state...],
    last_modified: route_specific_timestamp,
    public: false,
    template: false
  )
  return if performed?
end
```

For public routes, decide explicitly whether the route is:

- anonymous/publicly cacheable HTML
- private/authenticated only
- Inertia JSON that should remain `no-store`

See [libraries/pages_controller.rb](/Users/tuyenhx/Workspace/experiments/contextqmd_2/contextqmd-registry/app/controllers/libraries/pages_controller.rb) for the public/anonymous special-case split.

## Testing Rules

When adding a new cached route, add an integration test that proves:

1. HTML response returns an `ETag`
2. repeated HTML request with `If-None-Match` returns `304`
3. Inertia request does not reuse the HTML validator
4. repeated Inertia request with its own `ETag` returns `304`
5. flash-bearing responses stay `no-store`

Reference tests:

- [app/private_page_caching_test.rb](/Users/tuyenhx/Workspace/experiments/contextqmd_2/contextqmd-registry/test/integration/app/private_page_caching_test.rb)
- [admin/private_page_caching_test.rb](/Users/tuyenhx/Workspace/experiments/contextqmd_2/contextqmd-registry/test/integration/admin/private_page_caching_test.rb)
- [public_page_caching_test.rb](/Users/tuyenhx/Workspace/experiments/contextqmd_2/contextqmd-registry/test/integration/public_page_caching_test.rb)
- [library_page_caching_test.rb](/Users/tuyenhx/Workspace/experiments/contextqmd_2/contextqmd-registry/test/integration/library_page_caching_test.rb)
