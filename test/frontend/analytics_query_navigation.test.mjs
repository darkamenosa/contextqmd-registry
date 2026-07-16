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

async function loadQueryNavigationModule() {
  const workdir = await mkdtemp(
    path.join(tmpdir(), "analytics-query-navigation-")
  )
  const outfile = path.join(workdir, "analytics-query-navigation.cjs")

  try {
    await build({
      absWorkingDir: repoRoot,
      bundle: true,
      entryPoints: [
        "app/frontend/pages/admin/analytics/lib/query-navigation.ts",
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

const nextQuery = {
  period: "day",
  comparison: null,
  filters: { page: "/pricing" },
  labels: {},
  withImported: false,
}

test("query navigation keeps the current dialog by default", async () => {
  const { buildQueryNavigationPath } = await loadQueryNavigationModule()

  assert.equal(
    buildQueryNavigationPath({
      query: nextQuery,
      search: "?period=day",
      pathname: "/admin/analytics/_/pages",
      reportsPath: "/admin/analytics",
    }),
    "/admin/analytics/_/pages?f=is%2Cpage%2C%2Fpricing"
  )
})

test("query navigation can apply a filter and close a dialog atomically", async () => {
  const { buildQueryNavigationPath } = await loadQueryNavigationModule()

  assert.equal(
    buildQueryNavigationPath({
      query: nextQuery,
      search: "?period=day",
      pathname: "/admin/analytics/sites/site-123/_/pages",
      reportsPath: "/admin/analytics/sites/site-123",
      closeDialog: true,
    }),
    "/admin/analytics/sites/site-123?f=is%2Cpage%2C%2Fpricing"
  )
})
