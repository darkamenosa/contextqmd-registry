# Analytics Google Search Console Token Failure Note

This note documents the production Google Search Console failure observed on
April 7, 2026. It is intentionally diagnostic. The goal is to preserve the
facts, likely root cause, and deferred remediation options without forcing a
fix in the same branch.

## Summary

The admin analytics Search Terms panel failed in production for Google-filtered
queries, for example:

- `/admin/analytics?period=28d&f=is%2Csource%2CGoogle`

Two separate problems were present:

1. the Google OAuth refresh token was no longer usable
2. the app raised a secondary error while parsing Google's error payload

The directly confirmed upstream OAuth failure was:

- HTTP `400`
- `error = invalid_grant`
- `error_description = Token has been expired or revoked.`

The secondary app-side failure was:

- `TypeError: String does not have #dig method`

That secondary failure turned an actionable integration error into a generic
server-error state in the Search Terms panel.

## What Is Confirmed

Observed in production on April 7, 2026, Asia/Ho_Chi_Minh time:

- the active analytics site was `contextqmd.com`
- the active GSC connection existed and was marked active
- the connection was created on March 31, 2026 at `04:36:34 +07:00`
- the latest sync failed on April 7, 2026 at `11:34:53 +07:00`
- the latest sync error stored in the database was `String does not have #dig method`
- cached GSC query rows existed only from March 22, 2026 through April 4, 2026

The direct production token-refresh request to `https://oauth2.googleapis.com/token`
returned:

```json
{
  "error": "invalid_grant",
  "error_description": "Token has been expired or revoked."
}
```

The current request path also confirms why the failure shows up specifically in
the Search Terms panel:

1. `/admin/analytics?...source=Google` routes into the Search Terms response
2. Search Terms attempts request-time GSC coverage sync when cached coverage is
   missing for the selected period
3. the token refresh happens inside that sync path
4. the refresh fails before missing rows can be imported

Relevant code:

- `app/controllers/admin/analytics/referrers_controller.rb`
- `app/controllers/admin/analytics/base_controller.rb`
- `app/controllers/concerns/admin/analytics/google_search_console_context.rb`
- `app/models/analytics/google_search_console_connection.rb`
- `app/models/analytics/google_search_console/syncer.rb`
- `app/models/analytics/google_search_console/client.rb`

## Most Likely Root Cause

The most likely root cause is not a manual revocation by the operator.

The strongest current hypothesis is that the Google OAuth consent screen was
still in `Testing` when the connection was created. Google documents that for an
external OAuth app in `Testing`, refresh tokens expire after 7 days unless the
app requests only basic identity scopes. This app requests:

- `openid`
- `email`
- `https://www.googleapis.com/auth/webmasters.readonly`

Because `webmasters.readonly` is included, the 7-day exception for identity-only
scopes does not apply.

Why this is the leading hypothesis:

- connection created: March 31, 2026
- production failure surfaced: April 7, 2026
- that is an almost exact 7-day window
- the operator reported they did not manually revoke access

This is still a hypothesis, not a confirmed root cause. The only directly
confirmed OAuth fact is that Google returned `invalid_grant`.

Google also documents other valid causes for `invalid_grant` refresh-token
failure:

- user revoked access
- refresh token unused for six months
- refresh token limit exceeded for the user/client combination
- time-based access expired
- admin policy or session control invalidated the grant

Official reference:

- <https://developers.google.com/identity/protocols/oauth2>

## Why The UI Looked Worse Than The Real Problem

The integration failure alone should have been representable as a normal
unprocessable Search Terms response.

Instead, the app also crashed while parsing Google's error payload. Google may
return `error` as a string for token refresh failures. The client code assumed a
nested object and called `dig("error", "message")`, which raises when `error` is
a string.

That transformed:

- a recoverable `request_failed` integration error

into:

- a generic server-error experience in the admin panel

## Operational Consequence

Once cached rows no longer cover the requested date range, Google-filtered Search
Terms become fragile because the read path tries to fill coverage on demand.

This means:

- stale cached rows may still work for some periods
- broader periods such as `28d` can fail once they require fresh or older
  backfill beyond cached coverage
- the failure can appear panel-specific even though the real issue is the GSC
  integration state

## Deferred Fix Direction

Do not treat this as a single bug. It is two separate concerns:

1. OAuth lifecycle durability
2. dashboard behavior when the provider is degraded

The likely long-term direction is:

- move the Google OAuth consent screen to `Production` if it is still in
  `Testing`
- reconnect the GSC integration after that change
- keep automatic access-token refresh
- treat `invalid_grant` as a durable `reauth_required` state, not as a transient
  retry loop
- stop doing provider sync work on the user-facing read path for Search Terms
- prefer cached rows plus a visible stale-state banner over failing the panel
- keep parser-level error handling defensive so Google error-shape differences do
  not raise app exceptions

## Deferred Follow-Up Checklist

- Confirm Google Cloud OAuth consent screen publishing status for the production
  OAuth client.
- Confirm whether any Workspace admin session-control or policy setting could
  invalidate refresh tokens.
- Decide whether Search Terms should ever block on request-time sync.
- Add explicit integration states for `connected`, `stale`, and
  `reauth_required`.
- Add an admin reconnect prompt when Google returns `invalid_grant`.
- Preserve stale cached Search Terms results when reauthorization is required.

