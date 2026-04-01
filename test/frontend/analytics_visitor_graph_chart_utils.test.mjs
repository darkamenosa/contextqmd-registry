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

async function loadChartUtilsModule() {
  const workdir = await mkdtemp(
    path.join(tmpdir(), "analytics-visitor-graph-chart-utils-")
  )
  const outfile = path.join(workdir, "analytics-visitor-graph-chart-utils.cjs")

  try {
    await build({
      absWorkingDir: repoRoot,
      bundle: true,
      entryPoints: ["app/frontend/pages/admin/analytics/ui/visitor-graph/chart-utils.ts"],
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

test("top stat formatters preserve abbreviated and long values", async () => {
  const chartUtils = await loadChartUtilsModule()
  const visitorsStat = {
    name: "Unique visitors",
    value: 1532,
    graphMetric: "visitors",
  }

  assert.equal(chartUtils.formatTopStatValue(visitorsStat), "1.5k")
  assert.equal(chartUtils.formatTopStatLongValue(visitorsStat), "1,532")
  assert.equal(chartUtils.isTopStatValueAbbreviated(visitorsStat), true)
})

test("top stat long formatter leaves non-abbreviated metrics unchanged", async () => {
  const chartUtils = await loadChartUtilsModule()
  const rateStat = {
    name: "Conversion rate",
    value: 22.1,
    graphMetric: "conversion_rate",
  }

  assert.equal(chartUtils.formatTopStatValue(rateStat), "22.1%")
  assert.equal(chartUtils.formatTopStatLongValue(rateStat), "22.1%")
  assert.equal(chartUtils.isTopStatValueAbbreviated(rateStat), false)
})

test("views per visit uses shared numeric formatting", async () => {
  const chartUtils = await loadChartUtilsModule()
  const viewsPerVisitStat = {
    name: "Views per visit",
    value: 1.2,
    graphMetric: "views_per_visit",
  }

  assert.equal(chartUtils.formatTopStatValue(viewsPerVisitStat), "1.2")
  assert.equal(chartUtils.formatTopStatLongValue(viewsPerVisitStat), "1.2")
  assert.equal(chartUtils.isTopStatValueAbbreviated(viewsPerVisitStat), false)
})
