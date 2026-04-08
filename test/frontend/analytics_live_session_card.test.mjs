import assert from "node:assert/strict"
import { mkdtemp, rm, writeFile } from "node:fs/promises"
import { createRequire } from "node:module"
import { tmpdir } from "node:os"
import path from "node:path"
import test from "node:test"
import { build } from "esbuild"

const repoRoot = process.cwd()
const require = createRequire(import.meta.url)

async function renderLiveSessionCard(session) {
  const workdir = await mkdtemp(path.join(tmpdir(), "analytics-live-session-"))
  const outfile = path.join(workdir, "live-session-card-render.cjs")
  const avatarStubPath = path.join(workdir, "visitor-avatar-stub.mjs")

  await writeFile(
    avatarStubPath,
    `
      import React from "react"

      export default function VisitorAvatar({ name }) {
        return React.createElement("span", null, name)
      }
    `,
    "utf8"
  )

  try {
    await build({
      absWorkingDir: repoRoot,
      alias: {
        "@/components/analytics/visitor-avatar": avatarStubPath,
      },
      bundle: true,
      format: "cjs",
      nodePaths: [path.join(repoRoot, "node_modules")],
      outfile,
      platform: "node",
      stdin: {
        contents: `
          import React from "react"
          import ReactDOMServer from "react-dom/server"
          import LiveSessionCard from "./app/frontend/pages/admin/analytics/live/ui/live-session-card.tsx"

          const originalDateNow = Date.now
          Date.now = () => Date.parse("2026-03-28T10:05:15Z")

          const session = ${JSON.stringify(session)}
          const markup = ReactDOMServer.renderToStaticMarkup(
            <LiveSessionCard
              session={session}
              onClose={() => {}}
              onSelectSession={() => {}}
              sessionsAtCell={[session]}
            />
          )

          Date.now = originalDateNow

          export default markup
        `,
        loader: "tsx",
        resolveDir: repoRoot,
        sourcefile: "live-session-card-render.tsx",
      },
      tsconfig: path.join(repoRoot, "tsconfig.app.json"),
    })

    const module = require(outfile)
    return module.default
  } finally {
    await rm(workdir, { force: true, recursive: true })
  }
}

test("LiveSessionCard shows the current duration on first render", async () => {
  const markup = await renderLiveSessionCard({
    id: "session-1",
    sessionId: "session-1",
    visitId: 1,
    profileId: null,
    name: "Magenta Perch",
    email: null,
    identified: false,
    active: true,
    startedAt: "2026-03-28T10:00:00Z",
    lastSeenAt: "2026-03-28T10:05:10Z",
    source: "Direct / None",
    currentPage: "/admin/analytics/live",
    totalVisits: 4,
    recentEvents: [],
    city: "San Francisco",
    region: "California",
    country: "United States",
    countryCode: "US",
    deviceType: "desktop",
    os: "macOS",
    browser: "Safari",
  })

  assert.match(markup, /Session time/)
  assert.match(markup, /5 min 15 sec/)
  assert.doesNotMatch(markup, /0 min 00 sec/)
})
