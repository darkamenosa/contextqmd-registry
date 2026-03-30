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

async function loadSettingsTabsModule() {
  const workdir = await mkdtemp(path.join(tmpdir(), "analytics-settings-tabs-"))
  const outfile = path.join(workdir, "analytics-settings-tabs.cjs")

  try {
    await build({
      absWorkingDir: repoRoot,
      bundle: true,
      entryPoints: [
        "app/frontend/pages/admin/analytics/lib/settings-tabs.ts",
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

test("settings tabs read the tab param and default invalid values to tracking", async () => {
  const tabs = await loadSettingsTabsModule()

  assert.equal(
    tabs.getAnalyticsSettingsTabFromUrl("/admin/settings/analytics?tab=integrations"),
    "integrations"
  )
  assert.equal(
    tabs.getAnalyticsSettingsTabFromUrl("/admin/settings/analytics?tab=nope"),
    "tracking"
  )
  assert.equal(
    tabs.getAnalyticsSettingsTabFromUrl("/admin/settings/analytics"),
    "tracking"
  )
})

test("settings tabs preserve existing params when switching tabs", async () => {
  const tabs = await loadSettingsTabsModule()

  assert.equal(
    tabs.buildAnalyticsSettingsTabUrl(
      "/admin/settings/analytics?site=site-123",
      "integrations"
    ),
    "/admin/settings/analytics?site=site-123&tab=integrations"
  )
})

test("settings tabs keep the default tracking tab canonical", async () => {
  const tabs = await loadSettingsTabsModule()

  assert.equal(
    tabs.buildAnalyticsSettingsTabUrl(
      "/admin/settings/analytics?site=site-123&tab=integrations",
      "tracking"
    ),
    "/admin/settings/analytics?site=site-123"
  )
})
