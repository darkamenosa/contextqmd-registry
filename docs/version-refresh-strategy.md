# Version Refresh Strategy

This document describes the minimal strategy for keeping library versions fresh without full recrawls, download analytics, or manual curation.

## Goal

Detect when an upstream source has released a new version, and only then enqueue a full crawl.

This is explicitly **not** a generic “recrawl all docs regularly” system.

## Scope

This strategy only solves:

- when to check whether a library has a newer version
- when to enqueue a new crawl because of that newer version

This strategy does not try to solve:

- generic website content freshness
- fine-grained popularity scoring
- per-library download analytics
- version alias systems
- snapshot history

## What Exists Today

The current codebase already has the main pieces needed for a lightweight version-check flow:

- `LibrarySource` is the canonical upstream source record
- `CrawlRequest` is already the full crawl entrypoint
- `ProcessCrawlRequestJob` already owns the fetch/import lifecycle
- source-specific version extraction logic already exists in fetchers

Relevant files:

- `app/models/library_source.rb`
- `app/models/crawl_request.rb`
- `app/jobs/process_crawl_request_job.rb`
- `app/models/docs_fetcher/git.rb`
- `app/models/docs_fetcher/llms_txt.rb`
- `app/models/docs_fetcher/openapi.rb`
- `config/recurring.yml`
- `config/queue.yml`

## Important Constraints In Current Code

### 1. Recurring jobs are configured through `config/recurring.yml`

Today that file only defines a `production:` section. There is no recurring version-check job yet.

### 2. `CrawlRequest` immediately triggers a full crawl

Creating a `CrawlRequest` is not a cheap metadata operation. It will enqueue `ProcessCrawlRequestJob` after create.

That means version detection must happen before creating a `CrawlRequest`.

### 3. `LibrarySource` has almost no scheduling state

Today `library_sources` only stores:

- canonical source URL
- source type
- primary flag
- `last_crawled_at`

There is no notion of:

- last version check
- next version check
- version-change frequency

### 4. Queue workers only handle `default` and `crawl_website`

`config/queue.yml` currently runs:

- `default`
- `crawl_website`

So any new version-check jobs should use `default` unless a new worker queue is added explicitly.

### 5. Scheduled crawls cannot be anonymous

`crawl_requests.identity_id` is required, and admin crawl-request screens assume an identity email exists.

So background-created crawl requests need a dedicated system identity.

## Final Strategy

### Core idea

Run cheap version checks on a schedule.

Only create a `CrawlRequest` when:

- the source probe reports a meaningful change
- for versioned sources, the detected upstream version is newer than the latest version already stored
- for websites, the detected content signature changed from the last stored signature
- there is not already an active pending/processing crawl for that same change

### Source types included

Auto version-check:

- `github`
- `gitlab`
- `bitbucket`
- `git`
- `llms_txt`
- `openapi`
- `website`

Website sources do not use semantic version detection.

Instead, they use a lightweight homepage/sitemap content signature and trigger a refresh when that signature changes.

## Hot / Normal / Cold

Do not define these by downloads.

The codebase does not currently record per-library download or install counts, and adding analytics is extra work that does not directly solve version freshness.

Instead, define hot/normal/cold from observed release cadence.

### Bucket rules

- `hot`
  - last version change was within 30 days
- `cold`
  - `consecutive_no_change_checks >= 12`
- `normal`
  - everything else

### Check intervals

- `hot` => every 1 day
- `normal` => every 7 days
- `cold` => every 30 days

### New sources

All new version-checkable sources start as `normal`.

### Why this is the right tradeoff

- no download tracking
- no manual hot list
- no scoring model
- no extra analytics tables
- directly tied to the real problem: how often a source actually changes versions

## Minimal Schema Changes

Add these columns to `library_sources`:

- `last_version_check_at:datetime`
- `next_version_check_at:datetime`
- `last_version_change_at:datetime`
- `consecutive_no_change_checks:integer`, default `0`, null `false`
- `version_check_claimed_at:datetime`
- `last_probe_signature:string`

Recommended indexes:

- index on `next_version_check_at`

No bucket column is needed. The bucket is derived in Ruby from the fields above.

## Bootstrap And Scheduling Spread

Do not initialize all existing sources with the same `next_version_check_at`.

That would create a thundering herd and make the hourly scheduler permanently bursty.

For existing version-checkable sources:

- backfill `consecutive_no_change_checks = 0`
- set `next_version_check_at` to a randomized time within the next 7 days

For newly created version-checkable sources:

- initialize `next_version_check_at` when the `LibrarySource` is created
- default to `Time.current + 7.days + jitter`

Small jitter should also be applied when rescheduling checks so sources do not drift into the same minute over time.

## Model Behavior

Add version-check behavior directly to `LibrarySource`.

Suggested public methods:

- `version_checkable?`
- `version_check_bucket`
- `version_check_interval`
- `check_for_new_version!`
- `queue_version_refresh!`

Suggested logic:

```ruby
def version_checkable?
  source_type.in?(%w[github gitlab bitbucket git llms_txt openapi])
end

def version_check_bucket
  if last_version_change_at && last_version_change_at >= 30.days.ago
    "hot"
  elsif consecutive_no_change_checks >= 12
    "cold"
  else
    "normal"
  end
end

def version_check_interval
  case version_check_bucket
  when "hot"
    1.day
  when "cold"
    30.days
  else
    7.days
  end
end
```

## Scheduler Jobs

Add two jobs.

### `CheckDueLibrarySourcesJob`

Purpose:

- runs from `config/recurring.yml`
- selects due sources
- enqueues per-source checks

Suggested scope:

```ruby
LibrarySource.active
  .where(source_type: %w[github gitlab bitbucket git llms_txt openapi])
  .where("next_version_check_at <= ?", Time.current)
  .order(:next_version_check_at)
```

Queue:

- `default`

Do not hardcode a tiny fixed limit such as `200` for the whole run.

With tens of thousands of libraries, that will fall behind.

Instead:

- process due sources in batches
- keep each run bounded by a reasonable max batch count or runtime budget
- make sure the total hourly capacity comfortably exceeds the expected due volume

### `CheckLibrarySourceJob`

Purpose:

- performs one source check
- updates version-check timestamps
- creates a `CrawlRequest` only if a newer version exists

Queue:

- `default`

Suggested locking:

- use `source.with_lock`
- re-check due-ness inside the lock

## Source-Specific Version Probes

Do not create a generic probe framework yet.

Add one small public `probe_version(url)` method to the existing fetchers.

### Git

In `app/models/docs_fetcher/git.rb`:

- reuse existing `resolve_latest_tag`
- reuse existing `extract_version`
- return:
  - `version`
  - `ref`
  - explicit crawl URL

The explicit crawl URL matters because current git crawling only honors an exact ref when it is encoded in the URL.

Examples:

- GitHub: `/tree/<tag>`
- GitLab: `/-/tree/<tag>`
- Bitbucket: `/src/<tag>`

### llms.txt

In `app/models/docs_fetcher/llms_txt.rb`:

- fetch `llms.txt`
- reuse existing version extraction logic
- return:
  - `version`
  - original URL as crawl URL

### OpenAPI

In `app/models/docs_fetcher/openapi.rb`:

- fetch the spec
- read `info.version`
- return:
  - `version`
  - original URL as crawl URL

### Website

For websites:

- fetch a small HTML/XML payload from the source URL
- compute a stable content signature from the homepage body or sitemap entries
- return:
  - `signature`
  - original URL as crawl URL

## Comparing Against Existing Versions

Do not add a `last_seen_version` column initially.

Use the existing `versions` table as the truth.

The check job should:

1. detect upstream version
2. check whether that exact version already exists on the library
3. if not, find the highest stable version already stored on the library
4. compare using `Version.compare`

If the detected version is:

- missing => do nothing
- equal to an existing exact version => do nothing
- older than existing => do nothing
- newer than existing => enqueue a crawl

This keeps the state model smaller.

For websites, compare the detected signature against `library_sources.last_probe_signature`.

- no prior signature => store baseline, do not crawl yet
- same signature => do nothing
- changed signature => enqueue a crawl

## Creating The Follow-Up Crawl

Use the existing `CrawlRequest` model.

Do not add new `crawl_requests` columns initially.

Use `metadata` JSONB to record why the crawl exists:

```json
{
  "refresh_reason": "version_check",
  "detected_version": "8.1.2",
  "detected_ref": "v8.1.2"
}
```

Before creating a new crawl, check for an active duplicate:

- same `library_source_id`
- status in `pending` or `processing`
- same `metadata["detected_version"]`

If one exists, skip creating another crawl.

The scheduled crawl still needs to satisfy normal `CrawlRequest` validations.

That means the job must set at least:

- `identity`
- `url`
- `source_type`
- `requested_bundle_visibility`

For the first version, use the source URL, the existing source type, and a fixed bundle visibility such as `public`.

## System Identity

Scheduled crawls need a valid identity.

Smallest solution:

- create one dedicated system identity, for example `crawler@contextqmd.local`
- add a helper such as `CrawlRequest.system_identity`
- use it for scheduled version-refresh crawls

Do not make `crawl_requests.identity` optional in this first version.

That would ripple through admin pages and controller assumptions.

## Updating Version-Check State

### On version change

When a newer version is detected:

- create the crawl request
- set `last_version_check_at = now`
- set `last_version_change_at = now`
- reset `consecutive_no_change_checks = 0`
- set `next_version_check_at = now + 1.day`

### On no change

When no newer version is detected:

- set `last_version_check_at = now`
- increment `consecutive_no_change_checks`
- set `next_version_check_at = now + version_check_interval`

### On transient failure

Keep the behavior simple:

- set `last_version_check_at = now`
- set `next_version_check_at = now + 1.day`
- log the error
- let job retry policy handle temporary failures

No failure score is needed in the first version.

## On-Demand Wake-Up

Cold libraries should not be ignored forever.

Minimal improvement:

- if a library is requested and its primary source is overdue for a version check
- enqueue `CheckLibrarySourceJob`
- still serve the current stored result immediately

Good trigger points:

- public library show page
- API resolve endpoint

This gives long-tail libraries a cheap lazy refresh path without continuous polling.

This path should still respect the same due-ness guard.

Repeated page views should not force a new check when `next_version_check_at` is still in the future.

This is now enabled from:

- public library show page
- API resolve endpoint
- API library show endpoint

## Recurring Config

Add to `config/recurring.yml`:

```yml
production:
  check_due_library_sources:
    class: CheckDueLibrarySourcesJob
    queue: default
    schedule: every hour at minute 17
```

For local development, either:

- add a `development:` section too
- or run `CheckDueLibrarySourcesJob.perform_now` manually

## What We Are Explicitly Not Doing

Not in this first version:

- download-based popularity
- per-library analytics
- manual hot-list curation
- version aliases
- snapshot history
- webhook integrations

## Why This Is The Final Direction

This fits the current codebase:

- uses existing `LibrarySource`
- uses existing `CrawlRequest`
- uses existing fetcher parsing logic
- uses existing recurring-job setup
- avoids new systems unless they are required

And it solves the real problem:

- check cheaply
- crawl only when a new version exists
- automatically slow down stale libraries
- automatically speed up recently changing libraries
