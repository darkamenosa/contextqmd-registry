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
  return { storage }
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

test("analytics tracker falls back to in-memory storage when localStorage is unavailable", async () => {
  installBrowserStubs()
  globalThis.localStorage = {
    getItem() {
      throw new Error("storage blocked")
    },
    setItem() {
      throw new Error("storage blocked")
    },
    removeItem() {
      throw new Error("storage blocked")
    },
  }

  const { StandaloneAnalytics } = await loadTrackerModule()
  const analytics = new StandaloneAnalytics()
  analytics["visitorToken"] = "visitor-1"

  let posts = 0
  globalThis.fetch = async () => {
    posts += 1
    return { ok: true }
  }

  try {
    await analytics["ensureVisit"]()

    assert.equal(posts, 1)
    assert.ok(analytics["visitToken"])
    assert.ok(analytics["visitExpiresAt"])
  } finally {
    cleanupBrowserStubs()
  }
})

test("analytics tracker posts events with fetch keepalive even when sendBeacon exists", async () => {
  installBrowserStubs()
  const { StandaloneAnalytics } = await loadTrackerModule()
  const analytics = new StandaloneAnalytics()
  analytics["visitorToken"] = "visitor-1"
  analytics["createNewVisitToken"]()

  let beaconCalls = 0
  Object.defineProperty(globalThis, "navigator", {
    configurable: true,
    value: {
      sendBeacon() {
        beaconCalls += 1
        return false
      },
    },
  })

  const requests = []
  globalThis.fetch = async (url, options = {}) => {
    requests.push({ url, options })
    return { ok: true }
  }

  try {
    analytics["sendEvent"]({
      name: "pageview",
      page: "/",
      url: "https://contextqmd.com/",
      title: "Home",
      referrer: "",
      screenSize: "390x844",
    })

    await Promise.resolve()

    assert.equal(beaconCalls, 0)
    const eventRequest = requests.find((request) => request.url === "/ahoy/events")
    assert.ok(eventRequest)
    assert.equal(eventRequest.options.keepalive, true)
  } finally {
    cleanupBrowserStubs()
  }
})

test("analytics tracker still posts the pageview when visit creation fails", async () => {
  installBrowserStubs()
  const { StandaloneAnalytics } = await loadTrackerModule()
  const analytics = new StandaloneAnalytics()
  analytics["config"].useBeaconForEvents = false

  const requests = []
  globalThis.fetch = async (url, options = {}) => {
    requests.push({ url, options })
    if (url === "/ahoy/visits") throw new Error("visit create failed")
    return { ok: true }
  }

  try {
    await analytics["trackPageview"]()
    await Promise.resolve()

    assert.ok(requests.some((request) => request.url === "/ahoy/visits"))
    assert.ok(requests.some((request) => request.url === "/ahoy/events"))
  } finally {
    cleanupBrowserStubs()
  }
})

test("analytics tracker skips the server-tracked initial pageview and seeds follow-up state", async () => {
  installBrowserStubs()
  globalThis.window.analyticsConfig = {
    initialPageviewTracked: true,
    initialPageKey: "/about",
    useBeaconForEvents: false,
  }

  const requests = []
  globalThis.fetch = async (url, options = {}) => {
    requests.push({ url, options })
    return { ok: true }
  }

  const { StandaloneAnalytics } = await loadTrackerModule()
  const analytics = new StandaloneAnalytics()

  try {
    analytics.init()
    await Promise.resolve()

    assert.equal(requests.length, 0)
    assert.equal(analytics["lastTrackedPageKey"], "/about")
    assert.equal(analytics["lastTrackedHref"], "http://localhost/about")
    assert.ok(analytics["runningEngagementStart"] > 0)
  } finally {
    cleanupBrowserStubs()
  }
})

test("analytics tracker keeps server-issued tokens over stale local storage", async () => {
  const { storage } = installBrowserStubs()
  storage.set("ahoy_visit", "stale-visit")
  storage.set("ahoy_visit_expires", String(Date.now() + 60_000))
  storage.set("ahoy_visitor", "stale-visitor")

  globalThis.window.analyticsConfig = {
    initialPageviewTracked: true,
    initialPageKey: "/about",
    useBeaconForEvents: false,
  }

  globalThis.document.querySelector = (selector) => {
    if (selector === 'meta[name="ahoy-visit"]') {
      return { content: "server-visit" }
    }
    if (selector === 'meta[name="ahoy-visitor"]') {
      return { content: "server-visitor" }
    }
    return null
  }

  const requests = []
  globalThis.fetch = async (url, options = {}) => {
    requests.push({ url, options })
    return { ok: true }
  }

  const { StandaloneAnalytics } = await loadTrackerModule()
  const analytics = new StandaloneAnalytics()

  try {
    analytics.init()
    analytics["sendEvent"]({
      name: "engagement",
      page: "/about",
      url: "http://localhost/about",
      title: "About",
      referrer: "",
      screenSize: "1440x900",
    })
    await Promise.resolve()

    assert.equal(analytics["visitToken"], "server-visit")
    assert.equal(analytics["visitorToken"], "server-visitor")
    assert.equal(storage.get("ahoy_visit"), "server-visit")
    assert.equal(storage.get("ahoy_visitor"), "server-visitor")
    assert.ok(!requests.some((request) => request.url === "/ahoy/visits"))
    assert.ok(requests.some((request) => request.url === "/ahoy/events"))
  } finally {
    cleanupBrowserStubs()
  }
})
