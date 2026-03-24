import assert from "node:assert/strict"
import { mkdtemp, rm } from "node:fs/promises"
import { fileURLToPath } from "node:url"
import { createRequire } from "node:module"
import { tmpdir } from "node:os"
import path from "node:path"
import test from "node:test"
import { build } from "esbuild"

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "../..")
const require = createRequire(import.meta.url)

async function loadQueryScopeModule() {
  const workdir = await mkdtemp(path.join(tmpdir(), "analytics-query-scope-"))
  const outfile = path.join(workdir, "analytics-query-scope.cjs")

  try {
    await build({
      absWorkingDir: repoRoot,
      bundle: true,
      entryPoints: ["app/frontend/pages/admin/analytics/lib/query-scope.ts"],
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

test("analytics scoped query key can ignore panel mode changes", async () => {
  const scope = await loadQueryScopeModule()
  const baseQuery = {
    period: "day",
    comparison: null,
    filters: { page: "/login" },
    labels: {},
    withImported: false,
    metric: "views_per_visit",
    interval: "hour",
  }

  const pagesKey = scope.buildScopedQueryKey(
    { ...baseQuery, mode: "pages" },
    { omitMode: true }
  )
  const entryKey = scope.buildScopedQueryKey(
    { ...baseQuery, mode: "entry" },
    { omitMode: true }
  )
  const rawPagesKey = scope.buildScopedQueryKey({ ...baseQuery, mode: "pages" })
  const rawEntryKey = scope.buildScopedQueryKey({ ...baseQuery, mode: "entry" })

  assert.equal(pagesKey, entryKey)
  assert.notEqual(rawPagesKey, rawEntryKey)
})

test("analytics scoped query field stripping preserves non-mode filters", async () => {
  const scope = await loadQueryScopeModule()
  const query = {
    period: "day",
    comparison: "previous_period",
    filters: { source: "google" },
    labels: { source: "Google" },
    withImported: false,
    metric: "visitors",
    interval: "hour",
    mode: "entry",
  }

  assert.deepEqual(scope.stripQueryFields(query, { omitMode: true }), {
    period: "day",
    comparison: "previous_period",
    filters: { source: "google" },
    labels: { source: "Google" },
    withImported: false,
    metric: "visitors",
    interval: "hour",
  })
})

test("analytics scoped query key can ignore graph metric and interval changes", async () => {
  const scope = await loadQueryScopeModule()
  const query = {
    period: "day",
    comparison: null,
    filters: { source: "google" },
    labels: { source: "Google" },
    withImported: false,
    mode: "pages",
  }

  const firstKey = scope.buildScopedQueryKey(
    { ...query, metric: "visitors", interval: "hour" },
    { omitMetric: true, omitInterval: true }
  )
  const secondKey = scope.buildScopedQueryKey(
    { ...query, metric: "views_per_visit", interval: "day" },
    { omitMetric: true, omitInterval: true }
  )

  assert.equal(firstKey, secondKey)
})
