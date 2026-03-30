# Analytics Live Backport Note

The current branch fixes the live analytics refresh/broadcast mismatch by carrying the analytics scope through the async broadcast path and subscribing the live page to the matching stream.

For older versions that do not expose or route with `site_id`, do not backport the client-facing `site_id` contract directly.

Use these rules instead:

1. Keep the initial page payload and later cable payload under the exact same scope.
2. Carry that scope explicitly into the async broadcast job.
3. Resolve the live stream from existing old-version context, not from a newly introduced page prop if the old version does not have one.

Preferred old-version scope order:

- Existing tenant/account/workspace/property boundary, if one already exists.
- Hostname/referrer-derived site context, if the old version already uses host-based analytics scoping.
- Global scope only if the old version is truly single-site.

Avoid client-only fixes such as filtering or merging around bad broadcast payloads. If the server can publish the wrong live snapshot, the bug will reappear in other consumers.
