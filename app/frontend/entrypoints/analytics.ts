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
  visitsEndpoint: string
  // Filters
  excludePaths: string[]
  includePaths?: string[] // if provided, only paths matching any will be tracked (plausible-style)
  excludeAssets: string[]
  // Storage + transport
  useCookies: boolean // true = cookies (ahoy.js style); false = cookieless (localStorage). Default: false
  visitDurationMinutes: number // new visit after X minutes of inactivity. Default: 240 (4h)
  useBeaconForEvents: boolean // legacy flag; events use fetch keepalive by default
  trackVisits: boolean // create visit on frontend. Default: true
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
    analyticsConfig?: Partial<AnalyticsConfig>
  }
}

class StandaloneAnalytics {
  private readonly memoryStorage = new Map<string, string>()
  private visitToken: string | null = null
  private visitExpiresAt: number | null = null
  private visitorToken: string | null = null
  private lastTrackedHref: string | null = null
  // Dedup key for pageviews: pathname + search (or + hash if hashBasedRouting)
  private lastTrackedPageKey: string | null = null
  private config: AnalyticsConfig
  private ensureVisitPromise: Promise<boolean> | null = null
  private ensuredVisitToken: string | null = null
  private ensureVisitPromiseToken: string | null = null

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
      eventsEndpoint: "/ahoy/events",
      visitsEndpoint: "/ahoy/visits",
      // Defaults similar to our app; can be overridden by data-* attributes or window.analyticsConfig
      // Exclude internal/system endpoints to avoid accidental tracking
      excludePaths: [
        "/admin",
        "/app",
        "/login",
        "/logout",
        "/register",
        "/password",
        "/.well-known",
        "/ahoy",
        "/cable",
      ],
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
      useCookies: false,
      visitDurationMinutes: 240, // keep visit duration aligned with server-side analytics config (4h)
      useBeaconForEvents: false,
      trackVisits: true,
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
        this.config = { ...this.config, ...overrides }
      }
    } catch {
      // Ignore malformed runtime overrides and keep the default config.
    }

    // Read plausible-style include/exclude from script tag if present
    this.readScriptAttributes()

    // Load tokens (meta or storage). Visit creation stays lazy so excluded pages
    // do not create records just by loading the shared application layout.
    this.bootstrapIdentity()
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
  }

  private bootstrapIdentity(): void {
    // First try meta tokens (if server provided)
    const visitMeta = document.querySelector<HTMLMetaElement>(
      'meta[name="ahoy-visit"]'
    )
    const visitorMeta = document.querySelector<HTMLMetaElement>(
      'meta[name="ahoy-visitor"]'
    )
    if (visitMeta?.content) {
      this.visitToken = visitMeta.content
      this.ensuredVisitToken = visitMeta.content
      this.refreshVisitExpiry()
    }
    if (visitorMeta?.content) {
      this.visitorToken = visitorMeta.content
      this.storeVisitorToken(visitorMeta.content)
    }

    // Load from storage only for any missing identity pieces. When the server
    // already issued tokens for this document, those tokens are authoritative.
    this.ensureLocalIdentity()
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

    this.ensureLocalIdentity()
    void this.ensureVisit()

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
    this.ensureLocalIdentity()
    void this.ensureVisit()

    const event = {
      name: properties.name,
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

    const jsonPayload = {
      visit_token: this.visitToken,
      visitor_token: this.visitorToken,
      events: [event],
    }

    fetch(this.config.eventsEndpoint, {
      method: "POST",
      headers,
      body: JSON.stringify(jsonPayload),
      credentials: "same-origin",
      keepalive: true,
    }).catch(() => {
      /* never block app */
    })
  }

  private generateToken(): string {
    // Generate random token (UUIDv4-like hex)
    const cryptoObj =
      typeof globalThis !== "undefined" ? globalThis.crypto : undefined
    if (cryptoObj?.randomUUID) return cryptoObj.randomUUID().replace(/-/g, "")
    const array = new Uint8Array(16)
    if (cryptoObj?.getRandomValues) {
      cryptoObj.getRandomValues(array)
    } else {
      // Fallback to Math.random when Web Crypto is unavailable (very rare)
      for (let i = 0; i < array.length; i++)
        array[i] = Math.floor(Math.random() * 256)
    }
    return Array.from(array, (b) => b.toString(16).padStart(2, "0")).join("")
  }

  private getOrCreateVisitorToken(): string {
    const stored = this.getStoredVisitorToken()
    if (stored) return stored

    const token = this.generateToken()
    this.storeVisitorToken(token)
    return token
  }

  private getCSRFToken(): string | null {
    const meta = document.querySelector<HTMLMetaElement>(
      'meta[name="csrf-token"]'
    )
    return meta?.content || null
  }

  // ----- Visit lifecycle -----
  private ensureLocalIdentity(): void {
    if (!this.visitorToken) {
      this.visitorToken = this.getOrCreateVisitorToken()
    } else {
      this.storeVisitorToken(this.visitorToken)
    }

    const storedVisit = this.getStoredVisit()
    if (!this.visitToken && storedVisit) {
      this.visitToken = storedVisit.token
      this.visitExpiresAt = storedVisit.expiresAt
    }

    if (!this.visitToken || this.isVisitExpired()) {
      this.createNewVisitToken()
    } else {
      this.refreshVisitExpiry()
    }
  }

  private isVisitExpired(): boolean {
    if (!this.visitExpiresAt) return true
    return Date.now() > this.visitExpiresAt
  }

  private createNewVisitToken(): void {
    this.visitToken = this.generateToken()
    this.ensuredVisitToken = null
    this.ensureVisitPromise = null
    this.ensureVisitPromiseToken = null
    this.refreshVisitExpiry()
  }

  private refreshVisitExpiry(): void {
    if (!this.visitToken) return
    const ttlMs = this.config.visitDurationMinutes * 60 * 1000
    this.visitExpiresAt = Date.now() + ttlMs
    this.storeVisit(this.visitToken, this.visitExpiresAt)
  }

  private ensureActiveVisit(): Promise<boolean> {
    if (!this.visitToken) return Promise.resolve(false)
    // Send visit to server (JSON + CSRF header); mirrors ahoy.js createVisit
    const payload: Record<string, unknown> = {
      visit_token: this.visitToken,
      visitor_token: this.visitorToken,
      platform: "Web",
      landing_page: window.location.href,
      screen_width: window.innerWidth,
      screen_height: window.innerHeight,
      screen_size: `${window.innerWidth}x${window.innerHeight}`,
      js: true,
    }
    if (document.referrer) payload.referrer = document.referrer

    // Include UTM parameters from the landing URL (Plausible-compatible behavior)
    try {
      const params = new URLSearchParams(window.location.search)
      const utm_source =
        params.get("utm_source") || params.get("source") || params.get("ref")
      const utm_medium = params.get("utm_medium")
      const utm_campaign = params.get("utm_campaign")
      const utm_content = params.get("utm_content")
      const utm_term = params.get("utm_term")
      if (utm_source) payload.utm_source = utm_source
      if (utm_medium) payload.utm_medium = utm_medium
      if (utm_campaign) payload.utm_campaign = utm_campaign
      if (utm_content) payload.utm_content = utm_content
      if (utm_term) payload.utm_term = utm_term
    } catch {
      // Ignore malformed UTM params on the landing URL.
    }

    const headers: Record<string, string> = {
      "Content-Type": "application/json",
    }
    const csrf = this.getCSRFToken()
    if (csrf) headers["X-CSRF-Token"] = csrf

    return fetch(this.config.visitsEndpoint, {
      method: "POST",
      headers,
      body: JSON.stringify(payload),
      credentials: "same-origin",
      keepalive: true,
    })
      .then((response) => response.ok)
      .catch(() => {
        return false
      })
  }

  private ensureVisit(): Promise<void> {
    if (!this.config.trackVisits) return Promise.resolve()
    this.ensureLocalIdentity()

    const token = this.visitToken
    if (!token) return Promise.resolve()

    if (this.ensuredVisitToken === token) return Promise.resolve()

    if (this.ensureVisitPromise && this.ensureVisitPromiseToken === token) {
      return this.ensureVisitPromise.then(() => undefined)
    }

    const promise = this.ensureActiveVisit()
      .then((created) => {
        if (created && this.visitToken === token) {
          this.ensuredVisitToken = token
        }
        return created
      })
      .finally(() => {
        if (this.ensureVisitPromise === promise) {
          this.ensureVisitPromise = null
          this.ensureVisitPromiseToken = null
        }
      })

    this.ensureVisitPromise = promise
    this.ensureVisitPromiseToken = token
    return promise.then(() => undefined)
  }

  private getStoredVisit(): { token: string; expiresAt: number } | null {
    if (this.config.useCookies) {
      const token = this.getCookie("ahoy_visit")
      const exp = this.getCookie("ahoy_visit_expires")
      if (token && exp) return { token, expiresAt: parseInt(exp, 10) }
      return null
    } else {
      const token = this.getStorageItem("ahoy_visit")
      const exp = this.getStorageItem("ahoy_visit_expires")
      if (token && exp) return { token, expiresAt: parseInt(exp, 10) }
      return null
    }
  }

  private getStoredVisitorToken(): string | null {
    return this.config.useCookies
      ? this.getCookie("ahoy_visitor")
      : this.getStorageItem("ahoy_visitor")
  }

  private storeVisitorToken(token: string): void {
    if (this.config.useCookies) {
      this.setCookie("ahoy_visitor", token, 60 * 24 * 365 * 2)
    } else {
      this.setStorageItem("ahoy_visitor", token)
    }
  }

  private storeVisit(token: string, expiresAt: number): void {
    if (this.config.useCookies) {
      this.setCookie("ahoy_visit", token, this.config.visitDurationMinutes)
      // store absolute expiry (ms since epoch)
      this.setCookie(
        "ahoy_visit_expires",
        String(expiresAt),
        this.config.visitDurationMinutes
      )
    } else {
      this.setStorageItem("ahoy_visit", token)
      this.setStorageItem("ahoy_visit_expires", String(expiresAt))
    }
  }

  private getStorageItem(key: string): string | null {
    try {
      const stored = localStorage.getItem(key)
      return stored ?? this.memoryStorage.get(key) ?? null
    } catch {
      return this.memoryStorage.get(key) ?? null
    }
  }

  private setStorageItem(key: string, value: string): void {
    try {
      localStorage.setItem(key, value)
      this.memoryStorage.delete(key)
    } catch {
      this.memoryStorage.set(key, value)
    }
  }

  // ----- Cookie helpers -----
  private setCookie(name: string, value: string, ttlMinutes: number) {
    const d = new Date()
    d.setTime(d.getTime() + ttlMinutes * 60 * 1000)
    document.cookie = `${name}=${encodeURIComponent(value)}; expires=${d.toUTCString()}; path=/; samesite=lax`
  }
  private getCookie(name: string): string | null {
    const escapedName = name.replace(/[|\\{}()[\]^$+*?.]/g, "\\$&")
    const match = document.cookie.match(
      new RegExp(`(^|; )${escapedName}=([^;]*)`)
    )
    return match ? decodeURIComponent(match[2]) : null
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
            s.getAttribute("data-include") ||
            s.getAttribute("data-exclude") ||
            (s.src && s.src.includes("analytics"))
        )
      if (!el) return

      const includeAttr = el.getAttribute("data-include")
      const excludeAttr = el.getAttribute("data-exclude")
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

  // Wildcard matching similar to Plausible tracker
  // Supports '*' (single segment) and '**' (any), anchored to start and end by default
  private pathMatches(wildcardPath: string, actualPath: string): boolean {
    const wc = wildcardPath.trim()
    const pattern =
      "^" +
      wc
        .replace(/\./g, "\\.")
        .replace(/\*\*/g, ".*")
        .replace(/([^\\])\*/g, "$1[^\\s/]*") +
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
