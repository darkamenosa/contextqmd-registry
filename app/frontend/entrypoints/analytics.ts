/**
 * Standalone Analytics Tracker
 *
 * Universal tracker that works with:
 * - Multi-page apps (traditional server-rendered navigation)
 * - Single-page apps (React Router, Vue Router, Inertia.js, etc.)
 * - Hybrid apps (mix of both)
 *
 * Similar to Plausible.io, wraps the History API to detect navigation.
 * Usage: Add to <head> with <%= vite_typescript_tag "analytics" %>
 */

interface AnalyticsConfig {
  // Ahoy endpoints
  eventsEndpoint: string
  websiteId?: string
  siteToken?: string
  domainHint?: string
  // Filters
  excludePaths: string[]
  includePaths?: string[] // if provided, only paths matching any will be tracked (plausible-style)
  excludeAssets: string[]
  // Transport
  useBeaconForEvents: boolean // legacy flag; events use fetch keepalive by default
  initialPageviewTracked?: boolean // true when the server already tracked the current full-page load
  initialPageKey?: string // server-tracked dedupe key for the current page
  // Routing behavior
  hashBasedRouting?: boolean // when true, treat hash changes as navigation (off by default)
  // Dev
  debug?: boolean
}

declare global {
  interface Window {
    __analyticsInitialized?: boolean
    __analyticsQueue?: Array<[string, Record<string, unknown> | undefined]>
    analyticsConfig?: Partial<AnalyticsConfig> & {
      version?: number
      transport?: {
        eventsEndpoint?: string
      }
      site?: {
        websiteId?: string | null
        token?: string | null
        domainHint?: string | null
      }
      tracking?: {
        hashBasedRouting?: boolean
        initialPageviewTracked?: boolean
        initialPageKey?: string
      }
      filters?: {
        includePaths?: string[]
        excludePaths?: string[]
        excludeAssets?: string[]
      }
      debug?: boolean
    }
    analytics?: (name: string, props?: Record<string, unknown>) => void
  }
}

class StandaloneAnalytics {
  private lastTrackedHref: string | null = null
  // Dedup key for pageviews: pathname + search (or + hash if hashBasedRouting)
  private lastTrackedPageKey: string | null = null
  private config: AnalyticsConfig

  // Engagement tracking state (plausible-like)
  private listeningOnEngagement = false
  private currentEngagementIgnored = false
  private currentEngagementURL: string | null = null
  private currentEngagementMaxScrollDepth = -1
  private runningEngagementStart = 0
  private currentEngagementTime = 0
  private currentDocumentHeight = 0
  private maxScrollDepthPx = 0

  constructor() {
    this.config = {
      eventsEndpoint: "/analytics/events",
      // Defaults similar to our app; can be overridden by data-* attributes or window.analyticsConfig
      // Exclude internal/system endpoints to avoid accidental tracking
      excludePaths: ["/admin", "/.well-known", "/analytics", "/ahoy", "/cable"],
      excludeAssets: [
        ".png",
        ".jpg",
        ".jpeg",
        ".gif",
        ".svg",
        ".webp",
        ".ico",
        ".woff",
        ".woff2",
        ".ttf",
        ".eot",
        ".otf",
        ".pdf",
        ".zip",
        ".tar",
        ".gz",
        ".mp4",
        ".webm",
        ".mp3",
        ".wav",
        ".css",
        ".js",
        ".map",
        ".json",
      ],
      useBeaconForEvents: false,
      hashBasedRouting: false,
      debug: false,
    }
  }

  private debug(...args: unknown[]): void {
    if (this.config.debug) {
      console.warn("[analytics]", ...args)
    }
  }

  init(): void {
    if (typeof window === "undefined") return

    // Optional runtime overrides via window.analyticsConfig
    try {
      const overrides = window.analyticsConfig
      if (overrides && typeof overrides === "object") {
        this.config = { ...this.config, ...this.normalizeConfig(overrides) }
      }
    } catch {
      // Ignore malformed runtime overrides and keep the default config.
    }

    // Read plausible-style include/exclude from script tag if present
    this.readScriptAttributes()
    this.installPublicApi()

    this.bootstrapServerTrackedPageview()

    // Track initial page load only when the document is visible.
    // This prevents background prerenders/prefetches from counting and avoids
    // double pageviews when a hidden page is spun up by the browser.
    const trackWhenVisible = () => {
      if (document.visibilityState === "visible") {
        document.removeEventListener("visibilitychange", trackWhenVisible)
        void this.trackPageview()
      }
    }

    const triggerInitial = () => {
      if (document.visibilityState === "visible") {
        void this.trackPageview()
      } else {
        document.addEventListener("visibilitychange", trackWhenVisible)
      }
    }

    if (document.readyState === "loading") {
      document.addEventListener("DOMContentLoaded", triggerInitial)
    } else {
      triggerInitial()
    }

    // Listen for navigation events (works with both regular links and Inertia)
    this.setupNavigationListener()

    // Engagement and auto-capture listeners
    this.initEngagement()
    this.initAutoCapture()
    this.initDeclarativeGoalCapture()
  }

  private bootstrapServerTrackedPageview(): void {
    if (!this.config.initialPageviewTracked) return

    const href = window.location.href
    const pageKey = this.config.initialPageKey ?? this.currentPageKey()

    this.lastTrackedHref = href
    this.lastTrackedPageKey = pageKey
    this.postPageview({ url: href, page: pageKey })
  }

  private setupNavigationListener(): void {
    // Wrap history.pushState and history.replaceState to detect SPA navigation
    // This works for ANY SPA framework (React Router, Vue Router, Inertia, etc.)
    const originalPushState = history.pushState
    const originalReplaceState = history.replaceState

    if (originalPushState) {
      history.pushState = (...args) => {
        this.prePageview()
        originalPushState.apply(history, args)
        this.debug("pushState")
        void this.trackPageview()
      }
    }

    // Keep replaceState hook to catch rare replace-only navigations (e.g., Inertia Link with `replace`),
    // while dedup in trackPageview() ensures we don't double count when frameworks call replaceState
    // after pushState to update state/scroll.
    if (originalReplaceState) {
      history.replaceState = (...args) => {
        this.prePageview()
        originalReplaceState.apply(history, args)
        this.debug("replaceState")
        void this.trackPageview()
      }
    }

    // Listen for popstate (back/forward buttons)
    window.addEventListener("popstate", () => {
      this.prePageview()
      this.debug("popstate")
      void this.trackPageview()
    })

    // Optional: treat hash changes as navigation (off by default)
    if (this.config.hashBasedRouting) {
      window.addEventListener("hashchange", () => {
        this.prePageview()
        this.debug("hashchange")
        void this.trackPageview()
      })
    }

    window.addEventListener("pageshow", (event) => {
      if (!event.persisted) return
      this.prePageview()
      this.lastTrackedPageKey = null
      this.debug("pageshow persisted")
      void this.trackPageview()
    })
  }

  private async trackPageview(): Promise<void> {
    if (typeof window === "undefined") return

    // Skip tracking in iframes to avoid embedded/preview contexts skewing data
    try {
      if (window.top !== window.self) return
    } catch {
      /* cross-origin, treat as iframe */ return
    }

    const href = window.location.href
    const pathname = window.location.pathname
    const pathQuery = pathname + window.location.search
    const pageKey = this.currentPageKey()

    // Skip if same path+query as last tracked (ignore hash-only changes)
    if (this.lastTrackedPageKey === pageKey) return
    // Claim this pageKey immediately to avoid double-fire when pushState/replaceState
    // happen back-to-back during the same navigation tick (Inertia / SPA frameworks).
    this.lastTrackedPageKey = pageKey
    this.debug("trackPageview pageKey=", pageKey)

    // Skip excluded paths
    if (this.shouldExclude(pathname)) {
      this.pauseEngagement(href)
      this.lastTrackedHref = href
      return
    }

    const referrer = this.lastTrackedHref || document.referrer || ""

    // Plausible-style event name and props
    this.sendEvent({
      name: "pageview",
      page: pathQuery,
      url: href,
      title: document.title,
      referrer,
      screenSize: `${window.innerWidth}x${window.innerHeight}`,
    })

    this.lastTrackedHref = href
    this.postPageview({ url: href, page: pathQuery })
  }

  private currentPageKey(): string {
    const pathQuery = window.location.pathname + window.location.search
    return this.config.hashBasedRouting
      ? pathQuery + window.location.hash
      : pathQuery
  }

  private shouldExclude(pathname: string): boolean {
    const lowerPath = pathname.toLowerCase()

    // Exclude admin paths
    if (this.config.excludePaths.some((path) => lowerPath.startsWith(path))) {
      return true
    }

    // Exclude static assets
    if (this.config.excludeAssets.some((ext) => lowerPath.endsWith(ext))) {
      return true
    }

    // Exclude special files
    const specialFiles = [
      "/favicon.ico",
      "/robots.txt",
      "/sitemap.xml",
      "/manifest.json",
      "/browserconfig.xml",
      // Chrome DevTools well-known JSON
      "/.well-known/appspecific/com.chrome.devtools.json",
    ]
    if (specialFiles.includes(lowerPath)) {
      return true
    }

    // Exclude apple-touch-icon variants
    if (lowerPath.includes("apple-touch-icon")) {
      return true
    }

    // Apply plausible-style include/exclude rules
    const inc = this.config.includePaths && this.config.includePaths.length > 0
    if (inc) {
      const pass = this.config.includePaths!.some((p) =>
        this.pathMatches(p, lowerPath)
      )
      if (!pass) return true
    }
    if (this.config.excludePaths && this.config.excludePaths.length > 0) {
      if (this.config.excludePaths.some((p) => this.pathMatches(p, lowerPath)))
        return true
    }

    return false
  }

  private sendEvent(
    properties: {
      name: string
      page: string
      url: string
      title: string
      referrer: string
      screenSize: string
    },
    extra?: Record<string, unknown>
  ): void {
    if (typeof window === "undefined") return
    if (this.shouldExcludeEventPage(properties.page)) return

    const event = {
      name: properties.name,
      website_id: this.config.websiteId,
      site_token: this.config.siteToken,
      properties: {
        page: properties.page,
        url: properties.url,
        title: properties.title,
        referrer: properties.referrer,
        screen_size: properties.screenSize,
        ...(extra || {}),
      },
      time: Date.now() / 1000,
    }

    if (this.config.debug) {
      try {
        this.debug("sendEvent", {
          name: event.name,
          page: event.properties.page,
          url: event.properties.url,
        })
      } catch {
        // Ignore debug logging failures.
      }
    }

    // Prefer JSON + CSRF header via fetch keepalive for predictable browser
    // behavior across Safari/WebKit and easier end-to-end testing.
    const headers: Record<string, string> = {
      "Content-Type": "application/json",
    }
    const csrfToken = this.getCSRFToken()
    if (csrfToken) headers["X-CSRF-Token"] = csrfToken

    fetch(this.config.eventsEndpoint, {
      method: "POST",
      headers,
      // Privacy-first mode: the browser does not own analytics identity.
      // Ahoy resolves cookieless visitor identity server-side from the request.
      body: JSON.stringify({ events: [event] }),
      credentials: "same-origin",
      keepalive: true,
    }).catch(() => {
      /* never block app */
    })
  }

  private getCSRFToken(): string | null {
    const meta = document.querySelector<HTMLMetaElement>(
      'meta[name="csrf-token"]'
    )
    return meta?.content || null
  }

  // ----- Engagement (Plausible-like) -----
  private initEngagement(): void {
    this.currentDocumentHeight = this.getDocumentHeight()
    this.maxScrollDepthPx = this.getCurrentScrollDepthPx()

    window.addEventListener("load", () => {
      this.currentDocumentHeight = this.getDocumentHeight()
      let count = 0
      const interval = setInterval(() => {
        this.currentDocumentHeight = this.getDocumentHeight()
        if (++count === 15) clearInterval(interval)
      }, 200)
    })

    document.addEventListener("scroll", () => {
      this.currentDocumentHeight = this.getDocumentHeight()
      const cur = this.getCurrentScrollDepthPx()
      if (cur > this.maxScrollDepthPx) this.maxScrollDepthPx = cur
    })
  }

  private prePageview(): void {
    if (this.listeningOnEngagement) {
      this.triggerEngagement()
      this.currentDocumentHeight = this.getDocumentHeight()
      this.maxScrollDepthPx = this.getCurrentScrollDepthPx()
    }
  }

  private postPageview(payload: { url: string; page: string }): void {
    this.currentEngagementIgnored = false
    this.currentEngagementURL = payload.url
    this.currentEngagementMaxScrollDepth = -1
    this.currentEngagementTime = 0
    this.runningEngagementStart = Date.now()
    this.registerEngagementListeners()
  }

  private pauseEngagement(url: string): void {
    this.currentEngagementIgnored = true
    this.currentEngagementURL = url
    this.currentEngagementTime = 0
    this.runningEngagementStart = 0
  }

  private onVisibilityChange = (): void => {
    if (
      document.visibilityState === "visible" &&
      document.hasFocus() &&
      this.runningEngagementStart === 0
    ) {
      this.runningEngagementStart = Date.now()
    } else if (document.visibilityState === "hidden" || !document.hasFocus()) {
      this.currentEngagementTime = this.getEngagementTime()
      this.runningEngagementStart = 0
      this.triggerEngagement()
    }
  }

  private registerEngagementListeners(): void {
    if (!this.listeningOnEngagement) {
      document.addEventListener("visibilitychange", this.onVisibilityChange)
      window.addEventListener("blur", this.onVisibilityChange)
      window.addEventListener("focus", this.onVisibilityChange)
      this.listeningOnEngagement = true
    }
  }

  private getEngagementTime(): number {
    if (this.runningEngagementStart) {
      return (
        this.currentEngagementTime + (Date.now() - this.runningEngagementStart)
      )
    } else {
      return this.currentEngagementTime
    }
  }

  private triggerEngagement(): void {
    const engagementTime = this.getEngagementTime()
    const increasedScroll =
      this.currentEngagementMaxScrollDepth < this.maxScrollDepthPx
    // Send if first engagement (maxScrollDepth=-1), or scroll increased, or >=3s engaged
    if (
      !this.currentEngagementIgnored &&
      (increasedScroll ||
        engagementTime >= 3000 ||
        this.currentEngagementMaxScrollDepth === -1)
    ) {
      this.currentEngagementMaxScrollDepth = this.maxScrollDepthPx
      const sd =
        this.currentDocumentHeight > 0
          ? Math.round(
              (this.maxScrollDepthPx / this.currentDocumentHeight) * 100
            )
          : 0
      const url = this.currentEngagementURL || window.location.href
      this.sendEvent(
        {
          name: "engagement",
          page: window.location.pathname + window.location.search,
          url,
          title: document.title,
          referrer: document.referrer || "",
          screenSize: `${window.innerWidth}x${window.innerHeight}`,
        },
        { engaged_ms: engagementTime, scroll_depth: sd }
      )
      // Reset timers
      this.runningEngagementStart = 0
      this.currentEngagementTime = 0
    }
  }

  private shouldExcludeEventPage(page: string): boolean {
    const pathname = page.split("?")[0] || "/"
    return this.shouldExclude(pathname)
  }

  private getDocumentHeight(): number {
    const body = document.body as HTMLElement | null
    const el = document.documentElement as HTMLElement | null
    const b = body ?? ({} as HTMLElement)
    const d = el ?? ({} as HTMLElement)
    return Math.max(
      b.scrollHeight || 0,
      b.offsetHeight || 0,
      b.clientHeight || 0,
      d.scrollHeight || 0,
      d.offsetHeight || 0,
      d.clientHeight || 0
    )
  }

  private getCurrentScrollDepthPx(): number {
    const body = document.body as HTMLElement | null
    const el = document.documentElement as HTMLElement | null
    const viewportHeight = window.innerHeight || (el && el.clientHeight) || 0
    const scrollTop = window.scrollY || el?.scrollTop || body?.scrollTop || 0
    return this.currentDocumentHeight <= viewportHeight
      ? this.currentDocumentHeight
      : (scrollTop as number) + viewportHeight
  }

  // ----- Auto-capture: outbound links & file downloads -----
  private initAutoCapture(): void {
    const handler = (event: Event) => {
      // auxclick only for middle button
      if (event.type === "auxclick" && (event as MouseEvent).button !== 1)
        return
      const link = this.getLinkEl(event.target as Element | null)
      if (!link || !link.href) return
      try {
        const url = new URL(link.href, window.location.origin)
        // Ignore well-known DevTools config file
        if (url.pathname.startsWith("/.well-known/")) return
      } catch {
        // Ignore malformed URLs and keep checking the raw href.
      }
      const hrefWithoutQuery = link.href.split("?")[0]
      if (this.isOutboundLink(link)) {
        this.sendEvent({
          name: "Outbound Link: Click",
          page: window.location.pathname + window.location.search,
          url: link.href,
          title: document.title,
          referrer: document.referrer || "",
          screenSize: `${window.innerWidth}x${window.innerHeight}`,
        })
        return
      }
      if (this.isDownloadToTrack(hrefWithoutQuery)) {
        this.sendEvent({
          name: "File Download",
          page: window.location.pathname + window.location.search,
          url: hrefWithoutQuery,
          title: document.title,
          referrer: document.referrer || "",
          screenSize: `${window.innerWidth}x${window.innerHeight}`,
        })
      }
    }
    document.addEventListener("click", handler)
    document.addEventListener("auxclick", handler)
  }

  private initDeclarativeGoalCapture(): void {
    document.addEventListener("click", (event) => {
      const goalEl = this.getDeclarativeGoalEl(event.target as Element | null)
      if (!goalEl) return

      const goalName = goalEl.getAttribute("data-analytics-goal")?.trim()
      if (!goalName) return

      this.trackCustomEvent(goalName, this.extractDeclarativeGoalProps(goalEl))
    })
  }

  private installPublicApi(): void {
    if (typeof window === "undefined") return

    const queued = Array.isArray(window.__analyticsQueue)
      ? [...window.__analyticsQueue]
      : []

    window.analytics = (name: string, props?: Record<string, unknown>) => {
      this.trackCustomEvent(name, props)
    }

    window.__analyticsQueue = []

    for (const [name, props] of queued) {
      this.trackCustomEvent(name, props)
    }
  }

  private trackCustomEvent(
    name: string,
    props?: Record<string, unknown>
  ): void {
    const normalizedName = typeof name === "string" ? name.trim() : ""
    if (!normalizedName) return

    this.sendEvent(
      {
        name: normalizedName,
        page: window.location.pathname + window.location.search,
        url: window.location.href,
        title: document.title,
        referrer: document.referrer || "",
        screenSize: `${window.innerWidth}x${window.innerHeight}`,
      },
      props
    )
  }

  private getDeclarativeGoalEl(element: Element | null): Element | null {
    if (!element || typeof element.closest !== "function") return null
    return element.closest("[data-analytics-goal]")
  }

  private extractDeclarativeGoalProps(
    element: Element
  ): Record<string, unknown> | undefined {
    const attrs =
      "attributes" in element && element.attributes
        ? Array.from(element.attributes)
        : []

    const props = attrs.reduce<Record<string, unknown>>((memo, attr) => {
      const name = attr.name
      if (!name.startsWith("data-analytics-prop-")) return memo

      const rawKey = name.slice("data-analytics-prop-".length).trim()
      const key = rawKey.replace(/-/g, "_")
      if (!key) return memo

      memo[key] = attr.value
      return memo
    }, {})

    return Object.keys(props).length > 0 ? props : undefined
  }

  // Parse plausible-style data attributes from the <script> element that loaded this file
  private readScriptAttributes(): void {
    try {
      const scripts = Array.from(
        document.getElementsByTagName("script")
      ) as HTMLScriptElement[]
      // Heuristic: find a script whose src contains 'analytics' and either data-include or data-exclude set
      const el = scripts
        .reverse()
        .find(
          (s) =>
            s.getAttribute("data-website-id") ||
            s.getAttribute("data-include") ||
            s.getAttribute("data-exclude") ||
            (s.src && s.src.includes("/js/script"))
        )
      if (!el) return

      const websiteId = el.getAttribute("data-website-id")
      const domainHint = el.getAttribute("data-domain")
      const eventsEndpoint = el.getAttribute("data-api")
      const includeAttr = el.getAttribute("data-include")
      const excludeAttr = el.getAttribute("data-exclude")
      if (websiteId) this.config.websiteId = websiteId
      if (domainHint) this.config.domainHint = domainHint
      if (eventsEndpoint) this.config.eventsEndpoint = eventsEndpoint
      if (includeAttr)
        this.config.includePaths = includeAttr
          .split(",")
          .map((t) => t.trim())
          .filter(Boolean)
      if (excludeAttr)
        this.config.excludePaths = [
          ...this.config.excludePaths,
          ...excludeAttr
            .split(",")
            .map((t) => t.trim())
            .filter(Boolean),
        ]
    } catch {
      // Ignore malformed tracker script attributes.
    }
  }

  private normalizeConfig(
    overrides: Window["analyticsConfig"]
  ): Partial<AnalyticsConfig> {
    if (!overrides) return {}

    const normalized: Partial<AnalyticsConfig> = {}
    const transport = overrides.transport
    const site = overrides.site
    const tracking = overrides.tracking
    const filters = overrides.filters

    if (typeof overrides.eventsEndpoint === "string") {
      normalized.eventsEndpoint = overrides.eventsEndpoint
    } else if (typeof transport?.eventsEndpoint === "string") {
      normalized.eventsEndpoint = transport.eventsEndpoint
    }

    if (typeof overrides.websiteId === "string") {
      normalized.websiteId = overrides.websiteId
    } else if (typeof site?.websiteId === "string") {
      normalized.websiteId = site.websiteId
    }

    if (typeof overrides.siteToken === "string") {
      normalized.siteToken = overrides.siteToken
    } else if (typeof site?.token === "string") {
      normalized.siteToken = site.token
    }

    if (typeof overrides.domainHint === "string") {
      normalized.domainHint = overrides.domainHint
    } else if (typeof site?.domainHint === "string") {
      normalized.domainHint = site.domainHint
    }

    if (Array.isArray(overrides.includePaths))
      normalized.includePaths = overrides.includePaths
    else if (Array.isArray(filters?.includePaths))
      normalized.includePaths = filters.includePaths

    if (Array.isArray(overrides.excludePaths))
      normalized.excludePaths = overrides.excludePaths
    else if (Array.isArray(filters?.excludePaths))
      normalized.excludePaths = filters.excludePaths

    if (Array.isArray(overrides.excludeAssets))
      normalized.excludeAssets = overrides.excludeAssets
    else if (Array.isArray(filters?.excludeAssets))
      normalized.excludeAssets = filters.excludeAssets

    if (typeof overrides.useBeaconForEvents === "boolean") {
      normalized.useBeaconForEvents = overrides.useBeaconForEvents
    }

    if (typeof overrides.hashBasedRouting === "boolean") {
      normalized.hashBasedRouting = overrides.hashBasedRouting
    } else if (typeof tracking?.hashBasedRouting === "boolean") {
      normalized.hashBasedRouting = tracking.hashBasedRouting
    }

    if (typeof overrides.initialPageviewTracked === "boolean") {
      normalized.initialPageviewTracked = overrides.initialPageviewTracked
    } else if (typeof tracking?.initialPageviewTracked === "boolean") {
      normalized.initialPageviewTracked = tracking.initialPageviewTracked
    }

    if (typeof overrides.initialPageKey === "string") {
      normalized.initialPageKey = overrides.initialPageKey
    } else if (typeof tracking?.initialPageKey === "string") {
      normalized.initialPageKey = tracking.initialPageKey
    }

    if (typeof overrides.debug === "boolean") normalized.debug = overrides.debug

    return normalized
  }

  // Wildcard matching similar to Plausible tracker
  // Supports '*' (single segment) and '**' (any), anchored to start and end by default
  private pathMatches(wildcardPath: string, actualPath: string): boolean {
    const wc = wildcardPath.trim()
    const doubleWildcard = "__DOUBLE_WILDCARD__"
    const singleWildcard = "__SINGLE_WILDCARD__"
    const pattern =
      "^" +
      wc
        .replace(/\*\*/g, doubleWildcard)
        .replace(/\*/g, singleWildcard)
        .replace(/[.+?^${}()|[\]\\]/g, "\\$&")
        .split(doubleWildcard)
        .join(".*")
        .split(singleWildcard)
        .join("[^/]*") +
      "\\/?$"
    try {
      return new RegExp(pattern).test(actualPath)
    } catch {
      return false
    }
  }

  private getLinkEl(node: Element | null): HTMLAnchorElement | null {
    let el: Element | null = node
    let depth = 0
    while (el && depth < 5) {
      if (el instanceof HTMLAnchorElement && el.href) return el
      el = el.parentElement
      depth++
    }
    return null
  }

  private isOutboundLink(link: HTMLAnchorElement): boolean {
    try {
      return !!link.host && link.host !== window.location.host
    } catch {
      return false
    }
  }

  private isDownloadToTrack(url: string | undefined | null): boolean {
    if (!url) return false
    const DEFAULT_FILE_TYPES = [
      "pdf",
      "xlsx",
      "docx",
      "txt",
      "rtf",
      "csv",
      "exe",
      "key",
      "pps",
      "ppt",
      "pptx",
      "7z",
      "pkg",
      "rar",
      "gz",
      "zip",
      "avi",
      "mov",
      "mp4",
      "mpeg",
      "wmv",
      "midi",
      "mp3",
      "wav",
      "wma",
      "dmg",
    ]
    const ext = url.split(".").pop()?.toLowerCase()
    return !!ext && DEFAULT_FILE_TYPES.includes(ext)
  }
}

// Auto-initialize when script loads (singleton pattern)
if (typeof window !== "undefined") {
  // Prevent multiple instances
  if (!window.__analyticsInitialized) {
    const analytics = new StandaloneAnalytics()
    analytics.init()
    window.__analyticsInitialized = true
  }
}

export { StandaloneAnalytics }
