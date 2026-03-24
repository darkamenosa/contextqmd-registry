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

async function loadDashboardUrlStateModule() {
  const workdir = await mkdtemp(path.join(tmpdir(), "analytics-dashboard-url-"))
  const outfile = path.join(workdir, "analytics-dashboard-url.cjs")

  try {
    await build({
      absWorkingDir: repoRoot,
      bundle: true,
      entryPoints: [
        "app/frontend/pages/admin/analytics/lib/dashboard-url-state.ts",
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

test("graph url state helpers read graph-specific params", async () => {
  const state = await loadDashboardUrlStateModule()

  assert.equal(
    state.getGraphMetricFromSearch("?graph_metric=views_per_visit", undefined),
    "views_per_visit"
  )
  assert.equal(
    state.getGraphIntervalFromSearch("?graph_interval=hour", undefined),
    "hour"
  )
})

test("graph url state helpers fall back to legacy params", async () => {
  const state = await loadDashboardUrlStateModule()

  assert.equal(
    state.getGraphMetricFromSearch("?metric=visitors", undefined),
    "visitors"
  )
  assert.equal(
    state.getGraphIntervalFromSearch("?interval=day", undefined),
    "day"
  )
})

test("behaviors url state helpers read dedicated and legacy params", async () => {
  const state = await loadDashboardUrlStateModule()

  assert.equal(
    state.getBehaviorsFunnelFromSearch("?behaviors_funnel=Signup", undefined),
    "Signup"
  )
  assert.equal(
    state.getBehaviorsFunnelFromSearch("?funnel=Checkout", undefined),
    "Checkout"
  )
  assert.equal(
    state.getBehaviorsPropertyFromSearch("?behaviors_property=Plan"),
    "Plan"
  )
})

test("behaviors url state helpers ignore invalid placeholder values", async () => {
  const state = await loadDashboardUrlStateModule()

  assert.equal(
    state.getBehaviorsFunnelFromSearch("?behaviors_funnel=undefined", undefined),
    null
  )
  assert.equal(
    state.getBehaviorsPropertyFromSearch("?behaviors_property=null"),
    null
  )
})

test("dashboard url canonicalization removes legacy and redundant params", async () => {
  const state = await loadDashboardUrlStateModule()

  const params = state.canonicalizeDashboardSearchParams(
    "?metric=visits&interval=hour&mode=browsers&locations_mode=map&graph_metric=visit_duration&graph_interval=hour&behaviors_property=Utm+source&sources_mode=all&pages_mode=pages&devices_mode=operating-systems&behaviors_mode=funnels&period=day&with_imported=false&f=is,page,/libraries&f=is,source,Direct%20/%20None"
  )

  assert.equal(
    params.toString(),
    "graph_metric=visit_duration&devices_mode=operating-systems&behaviors_mode=funnels&f=is%2Cpage%2C%2Flibraries&f=is%2Csource%2CDirect+%2F+None"
  )
})

test("dashboard url canonicalization preserves sources_mode=all for channel drilldown", async () => {
  const state = await loadDashboardUrlStateModule()

  const params = state.canonicalizeDashboardSearchParams(
    "?sources_mode=all&f=is,channel,Paid%20Social"
  )

  assert.equal(
    params.toString(),
    "sources_mode=all&f=is%2Cchannel%2CPaid+Social"
  )
})
