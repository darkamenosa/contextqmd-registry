import assert from "node:assert/strict"
import { mkdtemp, rm } from "node:fs/promises"
import { createRequire } from "node:module"
import { tmpdir } from "node:os"
import path from "node:path"
import test from "node:test"
import { fileURLToPath } from "node:url"
import { build } from "esbuild"

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..")
const require = createRequire(import.meta.url)

async function loadAnalyticsApiModule() {
  const workdir = await mkdtemp(path.join(tmpdir(), "analytics-api-"))
  const outfile = path.join(workdir, "analytics-api.cjs")

  try {
    await build({
      absWorkingDir: repoRoot,
      bundle: true,
      entryPoints: ["app/frontend/pages/admin/analytics/api.ts"],
      format: "cjs",
      outfile,
      platform: "node",
      tsconfig: path.join(repoRoot, "tsconfig.app.json"),
    })

    return require(outfile)
  } finally {
    await rm(workdir, { force: true, recursive: true })
  }
}

test("analytics query params round-trip comma-containing filters and labels", async () => {
  const api = await loadAnalyticsApiModule()
  const fallback = {
    period: "day",
    comparison: null,
    filters: {},
    labels: {},
    withImported: false,
    matchDayOfWeek: true,
  }

  const query = {
    ...fallback,
    comparison: "previous_period",
    filters: { page: "/docs/foo,bar" },
    labels: { page: "Docs, page" },
    advancedFilters: [["contains", "source", "google,mail"]],
  }

  const search = `?${api.buildQueryParams(query)}`
  const parsed = api.parseQueryParams(search, fallback)

  assert.equal(parsed.filters.page, "/docs/foo,bar")
  assert.equal(parsed.labels.page, "Docs, page")
  assert.deepEqual(parsed.advancedFilters, [["contains", "source", "google,mail"]])
})

test("analytics query params preserve fallback matchDayOfWeek when URL omits it", async () => {
  const api = await loadAnalyticsApiModule()
  const fallback = {
    period: "day",
    comparison: null,
    filters: {},
    labels: {},
    withImported: false,
    matchDayOfWeek: true,
  }

  const parsed = api.parseQueryParams("?period=day", fallback)

  assert.equal(parsed.matchDayOfWeek, true)
})

test("analytics query params serialize false withImported explicitly", async () => {
  const api = await loadAnalyticsApiModule()
  const query = {
    period: "day",
    comparison: null,
    filters: {},
    labels: {},
    withImported: false,
  }

  const search = api.buildQueryParams(query)

  assert.match(search, /with_imported=false/)
})

test("analytics report query parsing ignores graph and panel UI params", async () => {
  const api = await loadAnalyticsApiModule()
  const fallback = {
    period: "day",
    comparison: null,
    filters: {},
    labels: {},
    withImported: false,
  }

  const parsed = api.parseQueryParams(
    "?period=7d&graph_metric=views_per_visit&graph_interval=hour&pages_mode=entry&mode=exit&metric=visitors&interval=day",
    fallback
  )

  assert.equal(parsed.period, "7d")
  assert.equal("mode" in parsed, false)
  assert.equal("metric" in parsed, false)
  assert.equal("interval" in parsed, false)
})

test("analytics report query merge preserves unrelated UI params", async () => {
  const api = await loadAnalyticsApiModule()
  const query = {
    period: "day",
    comparison: null,
    filters: { page: "/login" },
    labels: {},
    withImported: false,
  }

  const merged = api.mergeReportQueryParams(
    "?graph_metric=views_per_visit&pages_mode=entry&period=7d",
    query
  )

  assert.equal(merged.get("graph_metric"), "views_per_visit")
  assert.equal(merged.get("pages_mode"), "entry")
  assert.equal(merged.get("period"), null)
  assert.equal(merged.getAll("f")[0], "is,page,/login")
})

test("analytics initial report query resolution prefers the URL on the client", async () => {
  const api = await loadAnalyticsApiModule()
  const defaultQuery = {
    period: "day",
    comparison: null,
    filters: {},
    labels: {},
    withImported: false,
    matchDayOfWeek: true,
  }
  const initialQuery = {
    ...defaultQuery,
    period: "7d",
    filters: { page: "/server-prop" },
  }

  const resolved = api.resolveInitialReportQuery(
    "?period=custom&from=2026-03-01&to=2026-03-07&f=is,page,/from-url",
    initialQuery,
    defaultQuery
  )

  assert.equal(resolved.period, "custom")
  assert.equal(resolved.from, "2026-03-01")
  assert.equal(resolved.to, "2026-03-07")
  assert.deepEqual(resolved.filters, { page: "/from-url" })
})

test("analytics initial report query resolution falls back to initialQuery during SSR", async () => {
  const api = await loadAnalyticsApiModule()
  const defaultQuery = {
    period: "day",
    comparison: null,
    filters: {},
    labels: {},
    withImported: false,
    matchDayOfWeek: true,
  }
  const initialQuery = {
    ...defaultQuery,
    period: "7d",
    filters: { page: "/server-prop" },
  }

  const resolved = api.resolveInitialReportQuery(
    undefined,
    initialQuery,
    defaultQuery
  )

  assert.equal(resolved.period, "7d")
  assert.deepEqual(resolved.filters, { page: "/server-prop" })
})

test("analytics api surfaces structured JSON errors on failed requests", async () => {
  const api = await loadAnalyticsApiModule()
  const originalFetch = globalThis.fetch
  const query = {
    period: "day",
    comparison: null,
    filters: {},
    labels: {},
    withImported: false,
    matchDayOfWeek: true,
  }

  globalThis.fetch = async () =>
    new globalThis.Response(JSON.stringify({ errorCode: "not_configured" }), {
      status: 422,
      headers: { "Content-Type": "application/json" },
    })

  await assert.rejects(
    () => api.fetchSearchTerms(query, {}),
    (error) => {
      assert.equal(error instanceof api.AnalyticsApiError, true)
      assert.equal(error.status, 422)
      assert.equal(api.analyticsApiErrorCode(error), "not_configured")
      return true
    }
  )

  globalThis.fetch = originalFetch
})
