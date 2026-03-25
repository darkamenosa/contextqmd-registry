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

async function loadTopStatChangeModule() {
  const workdir = await mkdtemp(path.join(tmpdir(), "analytics-top-stat-change-"))
  const outfile = path.join(workdir, "analytics-top-stat-change.cjs")

  try {
    await build({
      absWorkingDir: repoRoot,
      bundle: true,
      entryPoints: ["app/frontend/pages/admin/analytics/lib/top-stat-change.ts"],
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

test("top stat change formatting matches plausible arrow rules", async () => {
  const topStatChange = await loadTopStatChangeModule()

  assert.equal(topStatChange.topStatChangeDirection(12), "up")
  assert.equal(topStatChange.topStatChangeDirection(-3), "down")
  assert.equal(topStatChange.topStatChangeDirection(0), "flat")

  assert.equal(topStatChange.formatTopStatChangeValue(100), "100%")
  assert.equal(topStatChange.formatTopStatChangeValue(-1.3), "1.3%")
  assert.equal(topStatChange.formatTopStatChangeValue(0.04), "0.04%")
})

test("top stat change tone inverts bounce rate trends", async () => {
  const topStatChange = await loadTopStatChangeModule()

  assert.equal(topStatChange.topStatChangeTone("visitors", 10), "good")
  assert.equal(topStatChange.topStatChangeTone("visitors", -10), "bad")
  assert.equal(topStatChange.topStatChangeTone("bounce_rate", 10), "bad")
  assert.equal(topStatChange.topStatChangeTone("bounce_rate", -10), "good")
})
