import assert from "node:assert/strict"
import { mkdtemp, rm, writeFile } from "node:fs/promises"
import { createRequire } from "node:module"
import { tmpdir } from "node:os"
import path from "node:path"
import test from "node:test"
import { build } from "esbuild"

const repoRoot = process.cwd()
const require = createRequire(import.meta.url)

async function renderPaginationFooter(pagination) {
  const workdir = await mkdtemp(path.join(tmpdir(), "pagination-footer-"))
  const stubPath = path.join(workdir, "inertia-react-stub.mjs")
  const outfile = path.join(workdir, "pagination-footer-render.cjs")

  await writeFile(stubPath, "export const router = { get() {} }\n", "utf8")

  try {
    await build({
      absWorkingDir: repoRoot,
      alias: {
        "@inertiajs/react": stubPath,
      },
      bundle: true,
      format: "cjs",
      outfile,
      platform: "node",
      stdin: {
        contents: `
          import React from "react"
          import ReactDOMServer from "react-dom/server"
          import { PaginationFooter } from "./app/frontend/components/shared/pagination-footer.tsx"

          const pagination = ${JSON.stringify(pagination)}
          const markup = ReactDOMServer.renderToStaticMarkup(
            <PaginationFooter pagination={pagination} />
          )

          export default markup
        `,
        loader: "tsx",
        resolveDir: repoRoot,
        sourcefile: "pagination-footer-render.tsx",
      },
      tsconfig: path.join(repoRoot, "tsconfig.app.json"),
    })

    const module = require(outfile)
    return module.default
  } finally {
    await rm(workdir, { force: true, recursive: true })
  }
}

test("PaginationFooter exposes landmark and accessible labels for icon buttons", async () => {
  const markup = await renderPaginationFooter({
    page: 2,
    pages: 4,
    from: 11,
    to: 20,
    total: 34,
    hasPrevious: true,
    hasNext: true,
  })

  assert.match(markup, /aria-label="Pagination"/)
  assert.match(markup, /aria-label="Previous page"/)
  assert.match(markup, /aria-label="Next page"/)
})
