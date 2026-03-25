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
  const workdir = await mkdtemp(path.join(tmpdir(), "analytics-visuals-"))
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

test("source visual helpers follow Plausible-style favicon mappings", async () => {
  const visuals = await loadModule(
    "app/frontend/pages/admin/analytics/lib/source-visuals.ts",
    "source-visuals.cjs"
  )

  assert.equal(visuals.getSourceFaviconDomain("ChatGPT"), "chatgpt.com")
  assert.equal(visuals.getSourceFaviconDomain("Perplexity"), "perplexity.ai")
  assert.equal(visuals.getSourceFaviconDomain("Slack"), "app.slack.com")
  assert.equal(visuals.getSourceFaviconDomain("Product Hunt"), "producthunt.com")
  assert.equal(
    visuals.getSourceFaviconDomain("https://canary.discord.com/channels/1"),
    "canary.discord.com"
  )
  assert.equal(visuals.getSourceFaviconDomain("Direct / None"), null)
  assert.equal(visuals.sourceNeedsLightBackground("chatgpt.com"), true)
  assert.equal(visuals.sourceNeedsLightBackground("github.com"), true)
  assert.equal(visuals.sourceNeedsLightBackground("perplexity.ai"), false)
})

test("device visual helpers cover Plausible browser and os mappings", async () => {
  const visuals = await loadModule(
    "app/frontend/pages/admin/analytics/lib/device-visuals.ts",
    "device-visuals.cjs"
  )

  assert.equal(visuals.getBrowserIcon("curl"), "curl.svg")
  assert.equal(visuals.getBrowserIcon("Huawei Browser Mobile"), "huawei.png")
  assert.equal(visuals.getBrowserIcon("QQ Browser"), "qq.png")
  assert.equal(visuals.getBrowserIcon("Ecosia"), "ecosia.png")

  assert.equal(visuals.getOSIcon("HarmonyOS 5"), "harmony_os.png")
  assert.equal(visuals.getOSIcon("Fire OS 8"), "fire_os.png")
  assert.equal(visuals.getOSIcon("KaiOS"), "kai_os.png")

  assert.equal(visuals.categorizeScreenSize("575x900"), "Mobile")
  assert.equal(visuals.categorizeScreenSize("576x900"), "Tablet")
  assert.equal(visuals.categorizeScreenSize("992x900"), "Laptop")
  assert.equal(visuals.categorizeScreenSize("1440x900"), "Desktop")
})
