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

async function loadPeriodUtilsModule() {
  const workdir = await mkdtemp(path.join(tmpdir(), "analytics-period-utils-"))
  const outfile = path.join(workdir, "period-utils.cjs")

  try {
    await build({
      absWorkingDir: repoRoot,
      bundle: true,
      entryPoints: ["app/frontend/pages/admin/analytics/ui/top-bar/period-utils.ts"],
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

test("24h period selection preserves comparison match mode", async () => {
  const periodUtils = await loadPeriodUtilsModule()
  const current = {
    period: "day",
    comparison: "previous_period",
    filters: {},
    labels: {},
    withImported: false,
    matchDayOfWeek: true,
    date: "2026-04-01",
    from: null,
    to: null,
  }

  const next = periodUtils.applyPeriodSelection(current, { value: "24h" })

  assert.equal(next.period, "24h")
  assert.equal(next.matchDayOfWeek, true)
  assert.equal(next.date, null)
})
