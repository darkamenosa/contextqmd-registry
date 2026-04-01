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

async function loadModule() {
  const workdir = await mkdtemp(path.join(tmpdir(), "analytics-metric-display-"))
  const outfile = path.join(workdir, "analytics-metric-display.cjs")

  try {
    await build({
      absWorkingDir: repoRoot,
      bundle: true,
      entryPoints: ["app/frontend/pages/admin/analytics/lib/metric-display.ts"],
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

test("metric display helpers preserve short and long number formatting", async () => {
  const metricDisplay = await loadModule()

  assert.equal(metricDisplay.formatMetric("visitors", 253234), "253k")
  assert.equal(metricDisplay.formatMetricLong("visitors", 253234), "253,234")
  assert.equal(metricDisplay.isMetricAbbreviated("visitors", 253234), true)
  assert.equal(metricDisplay.isMetricAbbreviated("visitors", 840), false)
})

test("metric display helpers respect panel-specific labels", async () => {
  const metricDisplay = await loadModule()
  const labels = { visitors: "Unique Entrances" }
  const conversionLabels = { conversionRate: "Conversion Rate" }

  assert.equal(
    metricDisplay.resolveMetricLabel("visitors", labels),
    "Unique Entrances"
  )
  assert.equal(metricDisplay.resolveMetricLabel("percentage", labels), "%")
  assert.equal(
    metricDisplay.resolveMetricLabel("percentage", labels, {
      compactPercentage: true,
    }),
    "%"
  )
  assert.equal(
    metricDisplay.resolveMetricLabel("conversion_rate", conversionLabels),
    "Conversion Rate"
  )
  assert.equal(
    metricDisplay.metricLabelSuffix("visitors", labels),
    " unique entrances"
  )
})
