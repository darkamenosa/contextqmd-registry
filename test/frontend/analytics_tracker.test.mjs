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

async function loadTrackerModule() {
  const workdir = await mkdtemp(path.join(tmpdir(), "analytics-tracker-"))
  const outfile = path.join(workdir, "analytics-tracker.cjs")

  try {
    await build({
      absWorkingDir: repoRoot,
      bundle: true,
      entryPoints: ["app/frontend/entrypoints/analytics.ts"],
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

function installBrowserStubs() {
  const storage = new Map()
  globalThis.localStorage = {
    getItem(key) {
      return storage.has(key) ? storage.get(key) : null
    },
    setItem(key, value) {
      storage.set(key, String(value))
    },
    removeItem(key) {
      storage.delete(key)
    },
  }
  globalThis.document = {
    referrer: "",
    title: "Test",
    cookie: "",
    readyState: "complete",
    visibilityState: "visible",
    querySelector() {
      return null
    },
    addEventListener() {},
    removeEventListener() {},
  }
  globalThis.window = {
    __analyticsInitialized: true,
    location: {
      href: "http://localhost/about",
      pathname: "/about",
      search: "",
      hash: "",
      host: "localhost",
    },
    innerWidth: 1440,
    innerHeight: 900,
    addEventListener() {},
    removeEventListener() {},
  }
  globalThis.history = {
    pushState() {},
    replaceState() {},
  }
  Object.defineProperty(globalThis, "navigator", {
    configurable: true,
    value: {
      sendBeacon() {
        return true
      },
    },
  })
  globalThis.fetch = async () => ({ ok: true })
}

function cleanupBrowserStubs() {
  delete globalThis.fetch
  delete globalThis.navigator
  delete globalThis.history
  delete globalThis.window
  delete globalThis.document
  delete globalThis.localStorage
}

test("analytics tracker refreshes visit expiry on repeated activity", async () => {
  installBrowserStubs()
  const { StandaloneAnalytics } = await loadTrackerModule()
  const analytics = new StandaloneAnalytics()

  analytics["visitorToken"] = "visitor-1"

  const originalNow = Date.now
  try {
    Date.now = () => 1_000
    analytics["createNewVisitToken"]()
    const firstExpiry = analytics["visitExpiresAt"]

    Date.now = () => 61_000
    await analytics["ensureVisit"]()

    assert.ok(analytics["visitExpiresAt"] > firstExpiry)
  } finally {
    Date.now = originalNow
    cleanupBrowserStubs()
  }
})

test("analytics tracker does not repost an ensured visit for the same token", async () => {
  installBrowserStubs()
  const { StandaloneAnalytics } = await loadTrackerModule()
  const analytics = new StandaloneAnalytics()
  analytics["visitorToken"] = "visitor-1"

  let posts = 0
  globalThis.fetch = async () => {
    posts += 1
    return { ok: true }
  }

  const originalNow = Date.now
  try {
    Date.now = () => 1_000
    await analytics["ensureVisit"]()
    await analytics["ensureVisit"]()

    assert.equal(posts, 1)

    const expiresAt = analytics["visitExpiresAt"]
    Date.now = () => expiresAt + 1
    await analytics["ensureVisit"]()

    assert.equal(posts, 2)
  } finally {
    Date.now = originalNow
    cleanupBrowserStubs()
  }
})
