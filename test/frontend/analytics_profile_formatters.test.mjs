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

async function loadModule(entryPoint, outfileName) {
  const workdir = await mkdtemp(path.join(tmpdir(), "analytics-profile-formatters-"))
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

test("profile session engagement formatter prefers engagement payloads", async () => {
  const formatters = await loadModule(
    "app/frontend/pages/admin/analytics/ui/profile/formatters.ts",
    "profile-formatters.cjs"
  )

  assert.equal(
    formatters.formatProfileSessionEngagement({
      engagedMsTotal: 285,
      durationSeconds: 0,
      pageviewsCount: 1,
      eventsCount: 2,
    }),
    "<1s"
  )

  assert.equal(
    formatters.formatProfileSessionEngagement({
      engagedMsTotal: 4200,
      durationSeconds: 0,
      pageviewsCount: 1,
      eventsCount: 2,
    }),
    "4s"
  )

  assert.equal(
    formatters.formatProfileSessionEngagement({
      engagedMsTotal: 0,
      durationSeconds: 0,
      pageviewsCount: 1,
      eventsCount: 1,
    }),
    "Single hit"
  )

  assert.equal(
    formatters.formatProfileSessionEngagement({
      engagedMsTotal: 0,
      durationSeconds: 5,
      pageviewsCount: 2,
      eventsCount: 2,
    }),
    "5s"
  )
})
