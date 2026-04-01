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
  const workdir = await mkdtemp(path.join(tmpdir(), "analytics-path-prefix-"))
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

test("analytics scoped paths stay under the selected site route", async () => {
  const paths = await loadModule(
    "app/frontend/pages/admin/analytics/lib/admin-analytics-host.ts",
    "analytics-path-prefix.cjs"
  )

  assert.equal(
    paths.resolveAdminAnalyticsScopePath("/admin/analytics/sites/site-123"),
    "/admin/analytics/sites/site-123"
  )
  assert.equal(
    paths.resolveAdminAnalyticsReportsPath("/admin/analytics/sites/site-123"),
    "/admin/analytics/sites/site-123"
  )
})

test("analytics dialog paths support site-scoped report routes", async () => {
  const dialogPath = await loadModule(
    "app/frontend/pages/admin/analytics/lib/dialog-path.ts",
    "analytics-dialog-path.cjs"
  )

  assert.equal(
    dialogPath.buildDialogPath(
      "sources",
      "period=day",
      "/admin/analytics/sites/site-123"
    ),
    "/admin/analytics/sites/site-123/_/sources?period=day"
  )
  assert.deepEqual(
    dialogPath.parseDialogFromPath(
      "/admin/analytics/sites/site-123/_/referrers/Google",
      "/admin/analytics/sites/site-123"
    ),
    { type: "referrers", source: "Google" }
  )
  assert.deepEqual(
    dialogPath.parseDialogFromPath(
      "/admin/analytics/sites/site-123/reports/_/sources",
      "/admin/analytics/sites/site-123"
    ),
    { type: "segment", segment: "sources" }
  )
})
