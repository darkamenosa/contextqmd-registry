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
  const workdir = await mkdtemp(path.join(tmpdir(), "analytics-live-utils-"))
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

test("liveSessionDurationSeconds uses the current clock only for active sessions", async () => {
  const liveUtils = await loadModule(
    "app/frontend/pages/admin/analytics/live/lib/live-utils.ts",
    "live-utils.cjs"
  )

  const session = {
    active: true,
    startedAt: "2026-03-28T10:00:00Z",
    lastSeenAt: "2026-03-28T10:00:20Z",
  }

  assert.equal(
    liveUtils.liveSessionDurationSeconds(
      session,
      Date.parse("2026-03-28T10:00:45Z")
    ),
    45
  )
})

test("liveSessionDurationSeconds freezes inactive sessions at their last activity", async () => {
  const liveUtils = await loadModule(
    "app/frontend/pages/admin/analytics/live/lib/live-utils.ts",
    "live-utils.cjs"
  )

  const session = {
    active: false,
    startedAt: "2026-03-28T10:00:00Z",
    lastSeenAt: "2026-03-28T10:00:28Z",
  }

  assert.equal(
    liveUtils.liveSessionDurationSeconds(
      session,
      Date.parse("2026-03-28T10:02:00Z")
    ),
    28
  )
})

test("liveEventLocation returns a compact live label", async () => {
  const liveUtils = await loadModule(
    "app/frontend/pages/admin/analytics/live/lib/live-utils.ts",
    "live-utils.cjs"
  )

  assert.equal(
    liveUtils.liveEventLocation({
      city: "San Francisco",
      region: "California",
      country: "United States",
      countryCode: "US",
    }),
    "San Francisco, CA"
  )
})

test("liveEventLocation keeps region abbreviations to disambiguate repeated city names", async () => {
  const liveUtils = await loadModule(
    "app/frontend/pages/admin/analytics/live/lib/live-utils.ts",
    "live-utils.cjs"
  )

  assert.equal(
    liveUtils.liveEventLocation({
      city: "Portland",
      region: "Oregon",
      country: "United States",
      countryCode: "US",
    }),
    "Portland, OR"
  )
})
