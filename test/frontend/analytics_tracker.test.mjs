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
  globalThis.document = {
    referrer: "",
    title: "Test",
    readyState: "complete",
    visibilityState: "visible",
    body: {
      scrollHeight: 1200,
      offsetHeight: 1200,
      clientHeight: 900,
      scrollTop: 0,
    },
    documentElement: {
      scrollHeight: 1200,
      offsetHeight: 1200,
      clientHeight: 900,
      scrollTop: 0,
    },
    querySelector() {
      return null
    },
    getElementsByTagName() {
      return []
    },
    addEventListener() {},
    removeEventListener() {},
    hasFocus() {
      return true
    },
  }

  globalThis.window = {
    __analyticsInitialized: true,
    analyticsConfig: undefined,
    location: {
      href: "http://localhost/about",
      pathname: "/about",
      search: "",
      hash: "",
      host: "localhost",
      origin: "http://localhost",
    },
    innerWidth: 1440,
    innerHeight: 900,
    scrollY: 0,
    addEventListener() {},
    removeEventListener() {},
  }
  globalThis.window.top = globalThis.window
  globalThis.window.self = globalThis.window

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
}

test("analytics tracker posts pageviews only through the events endpoint", async () => {
  installBrowserStubs()
  const { StandaloneAnalytics } = await loadTrackerModule()
  const analytics = new StandaloneAnalytics()

  const requests = []
  globalThis.fetch = async (url, options = {}) => {
    requests.push({ url, options })
    return { ok: true }
  }

  try {
    await analytics["trackPageview"]()
    await Promise.resolve()

    assert.equal(requests.length, 1)
    assert.equal(requests[0].url, "/ahoy/events")
    assert.equal(requests[0].options.keepalive, true)

    const body = JSON.parse(requests[0].options.body)
    assert.deepEqual(Object.keys(body), ["events"])
    assert.equal(body.events.length, 1)
    assert.equal(body.events[0].name, "pageview")
    assert.ok(!("visit_token" in body))
    assert.ok(!("visitor_token" in body))
  } finally {
    cleanupBrowserStubs()
  }
})

test("analytics tracker posts engagement events with fetch keepalive even when sendBeacon exists", async () => {
  installBrowserStubs()
  const { StandaloneAnalytics } = await loadTrackerModule()
  const analytics = new StandaloneAnalytics()

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
      name: "engagement",
      page: "/about",
      url: "http://localhost/about",
      title: "About",
      referrer: "",
      screenSize: "1440x900",
    })

    await Promise.resolve()

    assert.equal(beaconCalls, 0)
    const request = requests.find((entry) => entry.url === "/ahoy/events")
    assert.ok(request)
    assert.equal(request.options.keepalive, true)
  } finally {
    cleanupBrowserStubs()
  }
})

test("analytics tracker still posts the pageview when the server has not pre-tracked the document", async () => {
  installBrowserStubs()
  const { StandaloneAnalytics } = await loadTrackerModule()
  const analytics = new StandaloneAnalytics()

  const requests = []
  globalThis.fetch = async (url, options = {}) => {
    requests.push({ url, options })
    return { ok: true }
  }

  try {
    analytics.init()
    await Promise.resolve()

    assert.equal(requests.length, 1)
    assert.equal(requests[0].url, "/ahoy/events")
  } finally {
    cleanupBrowserStubs()
  }
})

test("analytics tracker skips the server-tracked initial pageview and seeds follow-up state", async () => {
  installBrowserStubs()
  globalThis.window.analyticsConfig = {
    initialPageviewTracked: true,
    initialPageKey: "/about",
    trackVisits: false,
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

test("analytics tracker path matching keeps ** semantics for nested paths", async () => {
  installBrowserStubs()
  const { StandaloneAnalytics } = await loadTrackerModule()
  const analytics = new StandaloneAnalytics()

  try {
    assert.equal(analytics["pathMatches"]("/docs/**", "/docs/a"), true)
    assert.equal(analytics["pathMatches"]("/docs/**", "/docs/a/b"), true)
    assert.equal(analytics["pathMatches"]("/docs/*", "/docs/a/b"), false)
  } finally {
    cleanupBrowserStubs()
  }
})
