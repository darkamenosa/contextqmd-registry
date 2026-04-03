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
  const documentListeners = new Map()
  const windowListeners = new Map()

  const addListener = (store, type, listener) => {
    const listeners = store.get(type) || []
    listeners.push(listener)
    store.set(type, listeners)
  }

  const removeListener = (store, type, listener) => {
    const listeners = store.get(type) || []
    store.set(
      type,
      listeners.filter((entry) => entry !== listener)
    )
  }

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
    addEventListener(type, listener) {
      addListener(documentListeners, type, listener)
    },
    removeEventListener(type, listener) {
      removeListener(documentListeners, type, listener)
    },
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
    addEventListener(type, listener) {
      addListener(windowListeners, type, listener)
    },
    removeEventListener(type, listener) {
      removeListener(windowListeners, type, listener)
    },
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
  globalThis.HTMLElement = class {}
  globalThis.HTMLAnchorElement = class extends globalThis.HTMLElement {}

  return {
    dispatchDocumentEvent(type, event) {
      for (const listener of documentListeners.get(type) || []) {
        listener(event)
      }
    },
  }
}

function cleanupBrowserStubs() {
  delete globalThis.fetch
  delete globalThis.HTMLAnchorElement
  delete globalThis.HTMLElement
  delete globalThis.navigator
  delete globalThis.history
  delete globalThis.window
  delete globalThis.document
}

async function flushTrackerQueue(analytics) {
  await analytics["flushEventQueue"]()
  await Promise.resolve()
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
    assert.equal(requests.length, 0)
    await flushTrackerQueue(analytics)

    assert.equal(requests.length, 1)
    assert.equal(requests[0].url, "/a/e")
    assert.equal(requests[0].options.keepalive, true)

    const body = JSON.parse(requests[0].options.body)
    assert.deepEqual(Object.keys(body), ["events"])
    assert.equal(body.events.length, 1)
    assert.equal(typeof body.events[0].id, "string")
    assert.ok(body.events[0].id.length > 0)
    assert.equal(body.events[0].name, "pageview")
    assert.ok(!("visit_token" in body))
    assert.ok(!("visitor_token" in body))
  } finally {
    cleanupBrowserStubs()
  }
})

test("analytics tracker drains every queued batch during keepalive flushes", async () => {
  installBrowserStubs()
  const { StandaloneAnalytics } = await loadTrackerModule()
  const analytics = new StandaloneAnalytics()

  const requests = []
  globalThis.fetch = async (url, options = {}) => {
    requests.push({ url, options })
    return { ok: true }
  }

  try {
    analytics["pendingEvents"] = Array.from({ length: 45 }, (_, index) => ({
      id: `evt-${index}`,
      name: `custom-${index}`,
      site_token: "signed-site-token",
      properties: {
        page: "/about",
        url: "http://localhost/about",
        title: "About",
        referrer: "",
        screen_size: "1440x900",
      },
      time: 1_000 + index,
    }))

    await analytics["flushEventQueue"]({ keepalive: true, drain: true })

    assert.equal(requests.length, 3)
    assert.deepEqual(
      requests.map((request) => JSON.parse(request.options.body).events.length),
      [20, 20, 5]
    )
    assert.deepEqual(
      requests.map((request) => request.options.keepalive),
      [true, true, true]
    )
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

    assert.equal(requests.length, 0)
    await flushTrackerQueue(analytics)

    assert.equal(beaconCalls, 0)
    const request = requests.find((entry) => entry.url === "/a/e")
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
    assert.equal(requests.length, 0)
    await flushTrackerQueue(analytics)

    assert.equal(requests.length, 1)
    assert.equal(requests[0].url, "/a/e")
  } finally {
    cleanupBrowserStubs()
  }
})

test("analytics tracker skips the server-tracked initial pageview and seeds follow-up state", async () => {
  installBrowserStubs()
  globalThis.window.analyticsConfig = {
    tracking: {
      initialPageviewTracked: true,
      initialPageKey: "/about",
    },
    site: {
      token: "signed-site-token",
      domainHint: "localhost",
    },
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
    assert.equal(analytics["config"].siteToken, "signed-site-token")
    assert.ok(analytics["runningEngagementStart"] > 0)
  } finally {
    cleanupBrowserStubs()
  }
})

test("analytics tracker includes the signed site token on client events", async () => {
  installBrowserStubs()
  globalThis.window.analyticsConfig = {
    site: { websiteId: "site_docs", token: "signed-site-token" },
  }

  const { StandaloneAnalytics } = await loadTrackerModule()
  const analytics = new StandaloneAnalytics()

  const requests = []
  globalThis.fetch = async (url, options = {}) => {
    requests.push({ url, options })
    return { ok: true }
  }

  try {
    analytics.init()
    await flushTrackerQueue(analytics)

    const body = JSON.parse(requests[0].options.body)
    assert.equal(body.events[0].site_token, "signed-site-token")
  } finally {
    cleanupBrowserStubs()
  }
})

test("analytics tracker exposes a public custom event api", async () => {
  installBrowserStubs()
  globalThis.window.analyticsConfig = {
    site: { websiteId: "site_docs", token: "signed-site-token" },
  }

  const { StandaloneAnalytics } = await loadTrackerModule()
  const analytics = new StandaloneAnalytics()

  const requests = []
  globalThis.fetch = async (url, options = {}) => {
    requests.push({ url, options })
    return { ok: true }
  }

  try {
    analytics.init()
    await flushTrackerQueue(analytics)
    requests.length = 0

    globalThis.window.analytics("signup", { plan: "pro" })
    assert.equal(requests.length, 0)
    await flushTrackerQueue(analytics)

    assert.equal(requests.length, 1)
    const body = JSON.parse(requests[0].options.body)
    assert.equal(body.events[0].name, "signup")
    assert.equal(body.events[0].site_token, "signed-site-token")
    assert.equal(body.events[0].properties.plan, "pro")
  } finally {
    cleanupBrowserStubs()
  }
})

test("analytics tracker supports declarative data-analytics-goal clicks", async () => {
  const browser = installBrowserStubs()
  globalThis.window.analyticsConfig = {
    site: { websiteId: "site_docs", token: "signed-site-token" },
  }

  const { StandaloneAnalytics } = await loadTrackerModule()
  const analytics = new StandaloneAnalytics()

  const requests = []
  globalThis.fetch = async (url, options = {}) => {
    requests.push({ url, options })
    return { ok: true }
  }

  const goalEl = {
    attributes: [
      { name: "data-analytics-goal", value: "signup" },
      { name: "data-analytics-prop-plan", value: "pro" },
      { name: "data-analytics-prop-cta-label", value: "hero" },
    ],
    getAttribute(name) {
      const attr = this.attributes.find((entry) => entry.name === name)
      return attr ? attr.value : null
    },
  }

  const childEl = {
    closest(selector) {
      return selector === "[data-analytics-goal]" ? goalEl : null
    },
  }

  try {
    analytics.init()
    await flushTrackerQueue(analytics)
    requests.length = 0

    browser.dispatchDocumentEvent("click", { target: childEl, type: "click" })
    assert.equal(requests.length, 0)
    await flushTrackerQueue(analytics)

    assert.equal(requests.length, 1)
    const body = JSON.parse(requests[0].options.body)
    assert.equal(body.events[0].name, "signup")
    assert.equal(body.events[0].properties.plan, "pro")
    assert.equal(body.events[0].properties.cta_label, "hero")
  } finally {
    cleanupBrowserStubs()
  }
})

test("analytics tracker batches multiple queued events into one request", async () => {
  installBrowserStubs()
  const { StandaloneAnalytics } = await loadTrackerModule()
  const analytics = new StandaloneAnalytics()

  const requests = []
  globalThis.fetch = async (url, options = {}) => {
    requests.push({ url, options })
    return { ok: true }
  }

  try {
    analytics["sendEvent"]({
      name: "pageview",
      page: "/about",
      url: "http://localhost/about",
      title: "About",
      referrer: "",
      screenSize: "1440x900",
    })
    analytics["sendEvent"]({
      name: "signup",
      page: "/about",
      url: "http://localhost/about",
      title: "About",
      referrer: "",
      screenSize: "1440x900",
    })

    assert.equal(requests.length, 0)
    await flushTrackerQueue(analytics)

    assert.equal(requests.length, 1)
    const body = JSON.parse(requests[0].options.body)
    assert.equal(body.events.length, 2)
    assert.equal(typeof body.events[0].id, "string")
    assert.equal(typeof body.events[1].id, "string")
    assert.notEqual(body.events[0].id, body.events[1].id)
    assert.deepEqual(
      body.events.map((event) => event.name),
      ["pageview", "signup"]
    )
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

test("analytics tracker does not exclude app and auth paths", async () => {
  installBrowserStubs()
  const { StandaloneAnalytics } = await loadTrackerModule()
  const analytics = new StandaloneAnalytics()

  try {
    assert.equal(analytics["shouldExclude"]("/app/2/dashboard"), false)
    assert.equal(analytics["shouldExclude"]("/login"), false)
    assert.equal(analytics["shouldExclude"]("/register"), false)
    assert.equal(analytics["shouldExclude"]("/password/new"), false)
    assert.equal(analytics["shouldExclude"]("/admin/dashboard"), true)
  } finally {
    cleanupBrowserStubs()
  }
})
