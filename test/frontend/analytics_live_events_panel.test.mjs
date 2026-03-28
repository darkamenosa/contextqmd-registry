import assert from "node:assert/strict"
import { mkdtemp, rm } from "node:fs/promises"
import { createRequire } from "node:module"
import { tmpdir } from "node:os"
import path from "node:path"
import test from "node:test"
import { build } from "esbuild"

const repoRoot = process.cwd()
const require = createRequire(import.meta.url)

async function renderLiveEventsPanel(events) {
  const workdir = await mkdtemp(path.join(tmpdir(), "analytics-live-panel-"))
  const outfile = path.join(workdir, "live-events-panel-render.cjs")

  try {
    await build({
      absWorkingDir: repoRoot,
      bundle: true,
      format: "cjs",
      nodePaths: [path.join(repoRoot, "node_modules")],
      outfile,
      platform: "node",
      stdin: {
        contents: `
          import React from "react"
          import ReactDOMServer from "react-dom/server"
          import LiveEventsPanel from "./app/frontend/pages/admin/analytics/live/ui/live-events-panel.tsx"

          const events = ${JSON.stringify(events)}
          const markup = ReactDOMServer.renderToStaticMarkup(
            <LiveEventsPanel
              title="Recent live activity"
              events={events}
              active={true}
              hydrated={false}
              variant="card"
            />
          )

          export default markup
        `,
        loader: "tsx",
        resolveDir: repoRoot,
        sourcefile: "live-events-panel-render.tsx",
      },
      tsconfig: path.join(repoRoot, "tsconfig.app.json"),
    })

    const module = require(outfile)
    return module.default
  } finally {
    await rm(workdir, { force: true, recursive: true })
  }
}

test("LiveEventsPanel shows only the latest 50 events", async () => {
  const baseTime = Date.parse("2026-03-28T10:00:00Z")
  const events = Array.from({ length: 60 }, (_, index) => ({
    id: index + 1,
    sessionId: String(index + 1),
    visitId: index + 1,
    profileId: null,
    name: `visitor-${index + 1}`,
    status: "anonymous",
    identified: false,
    active: true,
    eventName: "pageview",
    label: `Viewed page /page-${index + 1}`,
    occurredAt: new Date(baseTime + index * 1000).toISOString(),
    page: `/page-${index + 1}`,
    totalVisits: 1,
    scopedVisits: 1,
  }))

  const markup = await renderLiveEventsPanel(events)

  assert.doesNotMatch(markup, /\/page-1"/)
  assert.doesNotMatch(markup, /\/page-10"/)
  assert.match(markup, /\/page-11"/)
  assert.match(markup, /\/page-60"/)
})
