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

async function loadLiveStatsModule() {
  const workdir = await mkdtemp(path.join(tmpdir(), "analytics-live-subscription-"))
  const outfile = path.join(workdir, "live-stats.cjs")

  try {
    await build({
      absWorkingDir: repoRoot,
      bundle: true,
      entryPoints: ["app/frontend/pages/admin/analytics/live/hooks/use-live-stats.ts"],
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

test("live stats subscriptions include the explicit live subscription token when present", async () => {
  const liveStats = await loadLiveStatsModule()

  assert.deepEqual(liveStats.liveStatsChannelIdentifier("signed-token"), {
    channel: "AnalyticsChannel",
    subscription_token: "signed-token",
  })
})

test("live stats subscriptions omit the token when no live subscription is available", async () => {
  const liveStats = await loadLiveStatsModule()

  assert.deepEqual(liveStats.liveStatsChannelIdentifier(null), {
    channel: "AnalyticsChannel",
    subscription_token: undefined,
  })
})
