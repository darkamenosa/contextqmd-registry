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
  const workdir = await mkdtemp(path.join(tmpdir(), "analytics-live-events-"))
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

test("sortEventsAsc orders events from oldest to newest", async () => {
  const { sortEventsAsc } = await loadModule(
    "app/frontend/pages/admin/analytics/live/lib/live-event-buffer.ts",
    "live-event-buffer.cjs"
  )

  const now = Date.now()
  const events = [
    { id: 3, occurredAt: new Date(now - 2 * 60 * 1000).toISOString() },
    { id: 1, occurredAt: new Date(now - 14 * 60 * 1000).toISOString() },
    { id: 2, occurredAt: new Date(now - 11 * 60 * 1000).toISOString() },
  ]

  const sorted = sortEventsAsc(events)

  assert.deepEqual(
    sorted.map((event) => event.id),
    [1, 2, 3]
  )
})

test("sortEventsAsc preserves invalid timestamps at the end without throwing", async () => {
  const { sortEventsAsc } = await loadModule(
    "app/frontend/pages/admin/analytics/live/lib/live-event-buffer.ts",
    "live-event-buffer.cjs"
  )

  const events = [
    { id: 2, occurredAt: "not-a-date" },
    { id: 1, occurredAt: "2026-03-28T10:00:00Z" },
  ]

  const sorted = sortEventsAsc(events)

  assert.deepEqual(
    sorted.map((event) => event.id),
    [1, 2]
  )
})
