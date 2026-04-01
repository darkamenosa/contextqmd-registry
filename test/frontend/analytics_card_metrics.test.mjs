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

async function loadCardMetricsModule() {
  const workdir = await mkdtemp(path.join(tmpdir(), "analytics-card-metrics-"))
  const outfile = path.join(workdir, "card-metrics.cjs")

  try {
    await build({
      absWorkingDir: repoRoot,
      bundle: true,
      entryPoints: ["app/frontend/pages/admin/analytics/lib/card-metrics.ts"],
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

test("pickCardMetrics keeps visitors with the preferred secondary metric", async () => {
  const metrics = await loadCardMetricsModule()

  assert.deepEqual(
    metrics.pickCardMetrics(["events", "visitors", "percentage"]),
    ["visitors", "percentage"]
  )

  assert.deepEqual(
    metrics.pickCardMetrics(["conversionRate", "visitors", "events"]),
    ["visitors", "conversionRate"]
  )
})

test("limitListPayloadForCard sorts, trims, and updates hasMore consistently", async () => {
  const metrics = await loadCardMetricsModule()

  const payload = {
    results: [
      { name: "Zulu", visitors: 4, events: 10 },
      { name: "Alpha", visitors: 10, events: 5 },
      { name: "Beta", visitors: 10, events: 8 },
      { name: "Gamma", visitors: 3, events: 2 },
      { name: "Delta", visitors: 2, events: 7 },
      { name: "Echo", visitors: 1, events: 3 },
      { name: "Foxtrot", visitors: 6, events: 2 },
      { name: "Hotel", visitors: 5, events: 4 },
      { name: "India", visitors: 8, events: 1 },
      { name: "Juliet", visitors: 7, events: 6 },
    ],
    metrics: ["visitors", "events"],
    meta: {
      hasMore: false,
      skipImportedReason: null,
    },
  }

  const limited = metrics.limitListPayloadForCard(payload, {
    metrics: ["visitors"],
  })

  assert.deepEqual(limited.metrics, ["visitors"])
  assert.equal(limited.meta.hasMore, true)
  assert.equal(limited.results.length, 9)
  assert.deepEqual(
    limited.results.map((item) => item.name),
    ["Alpha", "Beta", "India", "Juliet", "Foxtrot", "Hotel", "Zulu", "Gamma", "Delta"]
  )
})

test("limitListPayloadForCard can sort by an explicit metric", async () => {
  const metrics = await loadCardMetricsModule()

  const payload = {
    results: [
      { name: "Alpha", visitors: 1, uniques: 2 },
      { name: "Beta", visitors: 10, uniques: 1 },
      { name: "Gamma", visitors: 5, uniques: 9 },
    ],
    metrics: ["visitors", "uniques"],
    meta: {
      hasMore: false,
      skipImportedReason: null,
    },
  }

  const limited = metrics.limitListPayloadForCard(payload, {
    metricKey: "uniques",
  })

  assert.deepEqual(
    limited.results.map((item) => item.name),
    ["Gamma", "Alpha", "Beta"]
  )
})
