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

test("profile session formatters keep duration and engaged time explicit", async () => {
  const formatters = await loadModule(
    "app/frontend/pages/admin/analytics/ui/profile/formatters.ts",
    "profile-formatters.cjs"
  )

  assert.equal(formatters.formatProfileSessionDuration(65), "1m 5s")
  assert.equal(formatters.formatProfileSessionDuration(0), "Single hit")

  assert.equal(formatters.formatProfileEngagedTime(285), "<1s")
  assert.equal(formatters.formatProfileEngagedTime(4200), "4s")
  assert.equal(formatters.formatProfileEngagedTime(0), null)
})
