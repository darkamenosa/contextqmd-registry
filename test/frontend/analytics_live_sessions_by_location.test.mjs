import assert from "node:assert/strict"
import { mkdtemp, rm, writeFile } from "node:fs/promises"
import { createRequire } from "node:module"
import { tmpdir } from "node:os"
import path from "node:path"
import test from "node:test"
import { build } from "esbuild"

const repoRoot = process.cwd()
const require = createRequire(import.meta.url)

async function renderSessionsByLocation(sessions) {
  const workdir = await mkdtemp(path.join(tmpdir(), "analytics-live-locations-"))
  const outfile = path.join(workdir, "sessions-by-location-render.cjs")
  const cardStubPath = path.join(workdir, "card-stub.mjs")

  await writeFile(
    cardStubPath,
    `
      import React from "react"

      export function Card({ children, className = "" }) {
        return React.createElement("section", { className }, children)
      }

      export function CardHeader({ children, className = "" }) {
        return React.createElement("header", { className }, children)
      }

      export function CardTitle({ children, className = "" }) {
        return React.createElement("h2", { className }, children)
      }

      export function CardContent({ children, className = "" }) {
        return React.createElement("div", { className }, children)
      }
    `,
    "utf8"
  )

  try {
    await build({
      absWorkingDir: repoRoot,
      alias: {
        "@/components/ui/card": cardStubPath,
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
          import { SessionsByLocation } from "./app/frontend/components/analytics/sessions-by-location.tsx"

          const sessions = ${JSON.stringify(sessions)}
          const markup = ReactDOMServer.renderToStaticMarkup(
            <SessionsByLocation sessions={sessions} />
          )

          export default markup
        `,
        loader: "tsx",
        resolveDir: repoRoot,
        sourcefile: "sessions-by-location-render.tsx",
      },
      tsconfig: path.join(repoRoot, "tsconfig.app.json"),
    })

    const module = require(outfile)
    return module.default
  } finally {
    await rm(workdir, { force: true, recursive: true })
  }
}

test("SessionsByLocation keeps unknown-only rows visible", async () => {
  const markup = await renderSessionsByLocation([
    {
      country: "Unknown",
      city: "",
      region: "",
      countryCode: "",
      visitors: 4,
    },
  ])

  assert.match(markup, /Sessions by location/)
  assert.match(markup, />Unknown</)
  assert.match(markup, />4</)
})

test("SessionsByLocation renders compact labels for known locations", async () => {
  const markup = await renderSessionsByLocation([
    {
      country: "United States",
      city: "San Francisco",
      region: "California",
      countryCode: "US",
      visitors: 6,
    },
  ])

  assert.match(markup, />San Francisco, CA</)
  assert.doesNotMatch(markup, /California/)
  assert.doesNotMatch(markup, /United States/)
})

test("SessionsByLocation preserves compact region disambiguation", async () => {
  const markup = await renderSessionsByLocation([
    {
      country: "United States",
      city: "Portland",
      region: "Oregon",
      countryCode: "US",
      visitors: 3,
    },
  ])

  assert.match(markup, />Portland, OR</)
})
