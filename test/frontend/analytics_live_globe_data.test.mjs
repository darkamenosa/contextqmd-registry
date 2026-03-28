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
  const workdir = await mkdtemp(path.join(tmpdir(), "analytics-live-globe-"))
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

test("live globe dots prefer live profile locations over raw visit dots", async () => {
  const globeData = await loadModule(
    "app/frontend/pages/admin/analytics/live/lib/globe-dots.ts",
    "globe-dots.cjs"
  )

  const dots = globeData.buildLiveGlobeDots(
    [
      {
        lat: 10.5,
        lng: 106.7,
        city: "Ho Chi Minh City",
        lastSeenAt: "2026-03-27T12:34:56.000Z",
      },
    ],
    [
      {
        lat: 40.7,
        lng: -74.0,
        city: "New York",
        type: "visitor",
        ts: 1,
      },
    ]
  )

  assert.equal(dots.length, 1)
  assert.equal(dots[0].lat, 10.5)
  assert.equal(dots[0].lng, 106.7)
  assert.equal(dots[0].city, "Ho Chi Minh City")
  assert.equal(dots[0].type, "visitor")
  assert.equal(dots[0].ts, Date.parse("2026-03-27T12:34:56.000Z"))
})

test("live globe dots fall back to visitor dots when live profiles lack coordinates", async () => {
  const globeData = await loadModule(
    "app/frontend/pages/admin/analytics/live/lib/globe-dots.ts",
    "globe-dots.cjs"
  )

  const fallback = [
    {
      lat: 51.5,
      lng: -0.12,
      city: "London",
      type: "visitor",
      ts: 123,
    },
  ]

  const dots = globeData.buildLiveGlobeDots(
    [{ lat: null, lng: null, city: "Unknown", lastSeenAt: null }],
    fallback
  )

  assert.deepEqual(dots, fallback)
})
