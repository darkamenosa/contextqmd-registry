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

async function loadPreferencesModule() {
  const workdir = await mkdtemp(path.join(tmpdir(), "analytics-preferences-"))
  const outfile = path.join(workdir, "preferences.cjs")

  try {
    await build({
      absWorkingDir: repoRoot,
      bundle: true,
      entryPoints: ["app/frontend/pages/admin/analytics/ui/visitor-graph/preferences.ts"],
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

test("analytics visitor graph initial metric selection stays SSR-safe", async () => {
  const preferences = await loadPreferencesModule()

  globalThis.window = {}
  globalThis.localStorage = {
    getItem() {
      return "bounce_rate"
    },
  }

  assert.equal(
    preferences.resolveInitialMetricSelection(
      ["visitors", "views_per_visit"],
      "visitors"
    ),
    "visitors"
  )

  assert.equal(
    preferences.resolvePreferredMetric(
      ["visitors", "views_per_visit", "bounce_rate"],
      "example.com",
      "visitors"
    ),
    "bounce_rate"
  )

  delete globalThis.window
  delete globalThis.localStorage
})

test("analytics visitor graph initial interval selection stays SSR-safe", async () => {
  const preferences = await loadPreferencesModule()

  globalThis.window = {}
  globalThis.localStorage = {
    getItem() {
      return "day"
    },
  }

  assert.equal(
    preferences.resolveInitialIntervalSelection("7d", "hour"),
    "hour"
  )

  assert.equal(
    preferences.resolvePreferredInterval("7d", "example.com", "hour"),
    "day"
  )

  delete globalThis.window
  delete globalThis.localStorage
})

test("analytics visitor graph initial selections still honor explicit URL state", async () => {
  const preferences = await loadPreferencesModule()

  assert.equal(
    preferences.resolveInitialMetricSelection(
      ["visitors", "views_per_visit"],
      "visitors",
      "views_per_visit"
    ),
    "views_per_visit"
  )

  assert.equal(
    preferences.resolveInitialIntervalSelection("day", "minute", "hour"),
    "hour"
  )
})
