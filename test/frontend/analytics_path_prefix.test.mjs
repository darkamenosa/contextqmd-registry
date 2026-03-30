import assert from "node:assert/strict"
import { mkdtemp, rm } from "node:fs/promises"
import { fileURLToPath } from "node:url"
import { createRequire } from "node:module"
import { tmpdir } from "node:os"
import path from "node:path"
import test from "node:test"
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
    "app/frontend/pages/admin/analytics/lib/path-prefix.ts",
    "analytics-path-prefix.cjs"
  )

  assert.equal(
    paths.analyticsScopePath("/admin/analytics/sites/site-123"),
    "/admin/analytics/sites/site-123"
  )
  assert.equal(
    paths.analyticsReportsPath("/admin/analytics/sites/site-123"),
    "/admin/analytics/sites/site-123"
  )
  assert.equal(
    paths.analyticsScopedPath(
      "/search_terms",
      "/admin/analytics/sites/site-123"
    ),
    "/admin/analytics/sites/site-123/search_terms"
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
      "/admin/analytics/sites/site-123/_/referrers/Google"
    ),
    { type: "referrers", source: "Google" }
  )
})
