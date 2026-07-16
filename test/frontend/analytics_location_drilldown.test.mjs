import assert from "node:assert/strict"
import { mkdtemp, rm } from "node:fs/promises"
import { createRequire } from "node:module"
import { tmpdir } from "node:os"
import path from "node:path"
import test from "node:test"
import { fileURLToPath } from "node:url"
import { build } from "esbuild"

const repoRoot = path.resolve(
  path.dirname(fileURLToPath(import.meta.url)),
  "../.."
)
const require = createRequire(import.meta.url)

async function loadLocationDrilldownModule() {
  const workdir = await mkdtemp(
    path.join(tmpdir(), "analytics-location-drilldown-")
  )
  const outfile = path.join(workdir, "analytics-location-drilldown.cjs")

  try {
    await build({
      absWorkingDir: repoRoot,
      bundle: true,
      entryPoints: [
        "app/frontend/pages/admin/analytics/lib/location-drilldown.ts",
      ],
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

const baseQuery = {
  period: "day",
  comparison: null,
  filters: { source: "Google" },
  labels: {},
  withImported: false,
}

test("location country drilldown navigates once to the filtered report", async () => {
  const { buildLocationDrilldownPath } = await loadLocationDrilldownModule()
  const path = buildLocationDrilldownPath({
    query: baseQuery,
    search: "?period=day&locations_mode=map",
    reportsPath: "/admin/analytics/sites/site-123",
    dimension: "country",
    value: "US",
    label: "United States",
  })
  const url = new URL(path, "https://example.test")

  assert.equal(url.pathname, "/admin/analytics/sites/site-123")
  assert.deepEqual(url.searchParams.getAll("f"), [
    "is,source,Google",
    "is,country,US",
  ])
  assert.deepEqual(url.searchParams.getAll("l"), [
    "country,United States",
  ])
  assert.equal(url.searchParams.get("locations_mode"), null)
})

test("location region drilldown preserves its country scope", async () => {
  const { buildLocationDrilldownPath } = await loadLocationDrilldownModule()
  const path = buildLocationDrilldownPath({
    query: {
      ...baseQuery,
      filters: { country: "US" },
      labels: { country: "United States" },
    },
    search:
      "?period=day&f=is,country,US&l=country,United%20States&locations_mode=regions",
    reportsPath: "/admin/analytics",
    dimension: "region",
    value: "Virginia",
    label: "Virginia",
  })
  const url = new URL(path, "https://example.test")

  assert.equal(url.pathname, "/admin/analytics")
  assert.deepEqual(url.searchParams.getAll("f"), [
    "is,country,US",
    "is,region,Virginia",
  ])
  assert.deepEqual(url.searchParams.getAll("l"), [
    "country,United States",
  ])
})
