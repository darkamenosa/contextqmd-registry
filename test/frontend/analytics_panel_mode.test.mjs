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

async function loadPanelModeModule() {
  const workdir = await mkdtemp(path.join(tmpdir(), "analytics-panel-mode-"))
  const outfile = path.join(workdir, "analytics-panel-mode.cjs")

  try {
    await build({
      absWorkingDir: repoRoot,
      bundle: true,
      entryPoints: ["app/frontend/pages/admin/analytics/lib/panel-mode.ts"],
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

test("panel mode helpers read shareable panel params from search", async () => {
  const panelMode = await loadPanelModeModule()

  assert.equal(
    panelMode.getPagesModeFromSearch("?pages_mode=entry", undefined),
    "entry"
  )
  assert.equal(
    panelMode.getDevicesModeFromSearch(
      "?devices_mode=operating-systems",
      undefined
    ),
    "operating-systems"
  )
  assert.equal(
    panelMode.getSourcesModeFromSearch("?sources_mode=utm-campaign", {
      filters: {},
    }),
    "utm-campaign"
  )
})

test("panel mode helpers preserve panel params when rebuilding analytics query strings", async () => {
  const panelMode = await loadPanelModeModule()
  const source = new globalThis.URLSearchParams(
    "period=day&pages_mode=entry&devices_mode=screen-sizes"
  )
  const target = new globalThis.URLSearchParams("period=7d&metric=visitors")

  panelMode.copyPanelModeSearchParams(source, target)

  assert.equal(target.get("pages_mode"), "entry")
  assert.equal(target.get("devices_mode"), "screen-sizes")
  assert.equal(target.get("metric"), "visitors")
})

test("panel mode helpers fall back to legacy mode param", async () => {
  const panelMode = await loadPanelModeModule()

  assert.equal(
    panelMode.getPagesModeFromSearch("?mode=entry", undefined),
    "entry"
  )
  assert.equal(
    panelMode.getSourcesModeFromSearch("?mode=utm-source", { filters: {} }),
    "utm-source"
  )
})

test("channel filters do not force channels mode", async () => {
  const panelMode = await loadPanelModeModule()

  assert.equal(
    panelMode.inferSourcesModeFromFilters({ channel: "Organic Social" }),
    null
  )
  assert.equal(
    panelMode.getSourcesModeFromSearch("", {
      filters: { channel: "Organic Social" },
    }),
    null
  )
})

test("utm filters still infer their matching source mode", async () => {
  const panelMode = await loadPanelModeModule()

  assert.equal(
    panelMode.inferSourcesModeFromFilters({ utm_campaign: "Launch" }),
    "utm-campaign"
  )
  assert.equal(
    panelMode.getSourcesModeFromSearch("", {
      filters: { utm_source: "newsletter" },
    }),
    "utm-source"
  )
})

test("device panel infers version breakdowns from fixed browser and os filters", async () => {
  const panelMode = await loadPanelModeModule()

  assert.equal(
    panelMode.inferDevicesModeFromFilters("browsers", { browser: "Chrome" }),
    "browser-versions"
  )
  assert.equal(
    panelMode.inferDevicesModeFromFilters("browsers", {
      browser_version: "136.0",
    }),
    "browser-versions"
  )
  assert.equal(
    panelMode.inferDevicesModeFromFilters("operating-systems", {
      os: "macOS",
    }),
    "operating-system-versions"
  )
  assert.equal(
    panelMode.inferDevicesModeFromFilters("operating-systems", {
      os_version: "14.4",
    }),
    "operating-system-versions"
  )
  assert.equal(
    panelMode.inferDevicesModeFromFilters("screen-sizes", { size: "Desktop" }),
    "screen-sizes"
  )
})

test("locations panel falls back when parent geo filters are removed", async () => {
  const panelMode = await loadPanelModeModule()

  assert.equal(
    panelMode.getLocationsModeAfterFilterChange(
      "cities",
      { country: "US", region: "California" },
      { country: "US" },
      "map"
    ),
    "regions"
  )
  assert.equal(
    panelMode.getLocationsModeAfterFilterChange(
      "regions",
      { country: "US" },
      {},
      "map"
    ),
    "map"
  )
  assert.equal(
    panelMode.getLocationsModeAfterFilterChange(
      "countries",
      { country: "US" },
      {},
      "map"
    ),
    null
  )
})
