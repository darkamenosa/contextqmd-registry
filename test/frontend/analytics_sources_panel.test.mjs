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

async function loadModule(entryPoint, outfileName) {
  const workdir = await mkdtemp(path.join(tmpdir(), "analytics-sources-panel-"))
  const outfile = path.join(workdir, outfileName)

  try {
    await build({
      absWorkingDir: repoRoot,
      bundle: true,
      entryPoints: [entryPoint],
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

test("sources panel helpers normalize invalid modes and expose stable labels", async () => {
  const helpers = await loadModule(
    "app/frontend/pages/admin/analytics/lib/sources-panel.ts",
    "analytics-sources-panel.cjs"
  )

  assert.equal(helpers.normalizeSourcesMode("invalid"), "all")
  assert.equal(helpers.getSourcesCardTitle("channels", "none"), "Top Channels")
  assert.equal(
    helpers.getSourcesCardTitle("all", "search-terms"),
    "Search Terms"
  )
  assert.equal(
    helpers.getSourcesDialogTitle("channels"),
    "Top Acquisition Channels"
  )
  assert.equal(
    helpers.getSourcesFirstColumnLabel("utm-campaign"),
    "UTM Campaign"
  )
  assert.equal(helpers.getSourcesFilterKey("utm-source"), "utm_source")
})

test("sources panel view state resolves dialog takeover modes from analytics routes", async () => {
  const helpers = await loadModule(
    "app/frontend/pages/admin/analytics/lib/sources-panel.ts",
    "analytics-sources-panel-view-state.cjs"
  )

  const google = helpers.resolveSourcesViewState(
    { type: "referrers", source: "Google" },
    {},
    "channels",
    null
  )

  assert.deepEqual(google, {
    mode: "all",
    activeSource: "Google",
    takeover: "search-terms",
    isGoogleActive: true,
    detailsOpen: true,
    refDetailsOpen: false,
  })

  const plain = helpers.resolveSourcesViewState(
    { type: "none" },
    { utm_source: "newsletter" },
    "all",
    "utm-source"
  )

  assert.deepEqual(plain, {
    mode: "utm-source",
    activeSource: undefined,
    takeover: "none",
    isGoogleActive: false,
    detailsOpen: false,
    refDetailsOpen: false,
  })
})

test("sources panel helper hides meaningless UTM lists dominated by none values", async () => {
  const helpers = await loadModule(
    "app/frontend/pages/admin/analytics/lib/sources-panel.ts",
    "analytics-sources-panel-utm.cjs"
  )

  assert.equal(
    helpers.hasUsableUtmData("utm-source", {
      results: [
        { name: "(none)", visitors: 95 },
        { name: "newsletter", visitors: 5 },
      ],
      metrics: ["visitors"],
      meta: { hasMore: false, skipImportedReason: null },
    }),
    false
  )

  assert.equal(
    helpers.hasUsableUtmData("utm-source", {
      results: [
        { name: "(none)", visitors: 89 },
        { name: "newsletter", visitors: 11 },
      ],
      metrics: ["visitors"],
      meta: { hasMore: false, skipImportedReason: null },
    }),
    true
  )
})
