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
