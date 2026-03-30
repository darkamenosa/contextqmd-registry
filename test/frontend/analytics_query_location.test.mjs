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

async function loadQueryLocationModule() {
  const workdir = await mkdtemp(path.join(tmpdir(), "analytics-query-location-"))
  const outfile = path.join(workdir, "analytics-query-location.cjs")

  try {
    await build({
      absWorkingDir: repoRoot,
      bundle: true,
      entryPoints: ["app/frontend/pages/admin/analytics/lib/query-location.ts"],
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

test("analytics query location keeps empty client search instead of reviving initial server filters", async () => {
  const location = await loadQueryLocationModule()

  const resolved = location.resolveAnalyticsLocation(
    {
      pathname: "/admin/analytics",
      search: "",
    },
    {
      pathname: "/admin/analytics",
      search: "?f=is%2Cpage%2C%2Flibraries%2Flowdefy",
    }
  )

  assert.equal(resolved.pathname, "/admin/analytics")
  assert.equal(resolved.search, "")
})

test("analytics query location falls back to initial url before the client location store is ready", async () => {
  const location = await loadQueryLocationModule()

  const resolved = location.resolveAnalyticsLocation(
    {
      pathname: "",
      search: "",
    },
    {
      pathname: "/admin/analytics",
      search: "?period=day",
    }
  )

  assert.equal(resolved.pathname, "/admin/analytics")
  assert.equal(resolved.search, "?period=day")
})
