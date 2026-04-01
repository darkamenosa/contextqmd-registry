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

async function loadPeriodModule() {
  const workdir = await mkdtemp(path.join(tmpdir(), "analytics-periods-"))
  const outfile = path.join(workdir, "periods.cjs")

  try {
    await build({
      absWorkingDir: repoRoot,
      bundle: true,
      entryPoints: ["app/frontend/pages/admin/analytics/lib/period.ts"],
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

test("analytics period registry centralizes picker labels and interval buckets", async () => {
  const period = await loadPeriodModule()

  assert.equal(period.getAnalyticsPeriodButtonLabel("realtime"), "Realtime (30m)")
  assert.equal(period.getAnalyticsPeriodButtonLabel("28d"), "Last 28 days")
  assert.deepEqual(period.getAnalyticsPeriodIntervals("91d"), [
    "day",
    "week",
    "month",
  ])

  const rollingRangeOptions = period.getAnalyticsPeriodPickerGroups()[1]

  assert.deepEqual(
    rollingRangeOptions.map(({ menuLabel, hint }) => ({ menuLabel, hint })),
    [
      { menuLabel: "Last 24 Hours", hint: "H" },
      { menuLabel: "Last 7 Days", hint: "W" },
      { menuLabel: "Last 28 Days", hint: "F" },
      { menuLabel: "Last 91 Days", hint: "N" },
    ]
  )

  assert.deepEqual(period.ANALYTICS_PERIOD_SHORTCUTS.H, { value: "24h" })
  assert.deepEqual(period.ANALYTICS_PERIOD_SHORTCUTS.M, {
    value: "month",
    setDate: "current",
  })
})

test("hidden supported periods stay out of the picker unless active", async () => {
  const period = await loadPeriodModule()

  const defaultGroups = period.getAnalyticsPeriodPickerGroups()
  const defaultOptions = defaultGroups.flat()
  const activeGroups = period.getAnalyticsPeriodPickerGroups("6mo")
  const activeOptions = activeGroups.flat()

  assert.equal(
    defaultOptions.some((option) => option.value === "6mo"),
    false
  )
  assert.equal(
    activeOptions.some((option) => option.value === "6mo"),
    true
  )
  assert.deepEqual(period.ANALYTICS_PERIOD_SHORTCUTS.S, { value: "6mo" })
})
