import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
  type ReactNode,
} from "react"

import {
  mergeReportQueryParams,
  parseQueryParams,
  resolveInitialReportQuery,
  sanitizeReportQuery,
} from "./api"
import { canonicalizeDashboardSearchParams } from "./lib/dashboard-url-state"
import type { AnalyticsQuery } from "./types"

const LOCATION_CHANGE_EVENT = "analytics:location-change"

export type QueryContextValue = {
  query: AnalyticsQuery
  pathname: string
  search: string
  updateQuery: (
    updater: (current: AnalyticsQuery) => AnalyticsQuery,
    options?: { history?: "push" | "replace" }
  ) => void
}

const QueryContext = createContext<QueryContextValue | null>(null)

export function QueryProvider({
  initialQuery,
  defaultQuery,
  children,
}: {
  initialQuery: AnalyticsQuery
  defaultQuery: AnalyticsQuery
  children: ReactNode
}) {
  const [query, setQuery] = useState<AnalyticsQuery>(() =>
    resolveInitialReportQuery(
      typeof window === "undefined" ? undefined : window.location.search,
      initialQuery,
      defaultQuery
    )
  )
  const [pathname, setPathname] = useState(() =>
    typeof window === "undefined" ? "" : window.location.pathname
  )
  const [search, setSearch] = useState(() =>
    typeof window === "undefined" ? "" : window.location.search
  )
  const isFirstRender = useRef(true)
  const suppressNextPush = useRef(false)
  const defaultQueryRef = useRef(defaultQuery)
  const nextHistoryModeRef = useRef<"push" | "replace">("push")

  useEffect(() => {
    defaultQueryRef.current = sanitizeReportQuery(defaultQuery)
    suppressNextPush.current = true
    setQuery(
      resolveInitialReportQuery(
        typeof window === "undefined" ? undefined : window.location.search,
        initialQuery,
        defaultQuery
      )
    )
    if (typeof window !== "undefined") {
      setPathname(window.location.pathname)
      setSearch(window.location.search)
    }
  }, [defaultQuery, initialQuery])

  const updateQuery = useCallback(
    (
      updater: (current: AnalyticsQuery) => AnalyticsQuery,
      options?: { history?: "push" | "replace" }
    ) => {
      setQuery((current) => {
        const next = updater(current)
        if (next !== current) {
          nextHistoryModeRef.current = options?.history ?? "push"
        }
        return next
      })
    },
    []
  )

  useEffect(() => {
    if (typeof window === "undefined") return

    const handlePopState = () => {
      suppressNextPush.current = true
      setQuery(
        parseQueryParams(window.location.search, defaultQueryRef.current)
      )
      setPathname(window.location.pathname)
      setSearch(window.location.search)
    }

    const handleLocationChange = () => {
      setPathname(window.location.pathname)
      setSearch(window.location.search)
    }

    const originalPushState = window.history.pushState
    const originalReplaceState = window.history.replaceState

    window.history.pushState = function (
      ...args: Parameters<History["pushState"]>
    ) {
      originalPushState.apply(this, args)
      window.dispatchEvent(new Event(LOCATION_CHANGE_EVENT))
    }

    window.history.replaceState = function (
      ...args: Parameters<History["replaceState"]>
    ) {
      originalReplaceState.apply(this, args)
      window.dispatchEvent(new Event(LOCATION_CHANGE_EVENT))
    }

    window.addEventListener("popstate", handlePopState)
    window.addEventListener(LOCATION_CHANGE_EVENT, handleLocationChange)

    return () => {
      window.history.pushState = originalPushState
      window.history.replaceState = originalReplaceState
      window.removeEventListener("popstate", handlePopState)
      window.removeEventListener(LOCATION_CHANGE_EVENT, handleLocationChange)
    }
  }, [])

  useEffect(() => {
    if (typeof window === "undefined") return

    const current = window.location.search.replace(/^\?/, "")
    const canonical = canonicalizeDashboardSearchParams(
      window.location.search
    ).toString()
    if (canonical === current) return

    window.history.replaceState(
      {},
      "",
      `${window.location.pathname}${canonical ? `?${canonical}` : ""}`
    )
  }, [pathname, search])

  // Keep URL query string in sync with local query state (push new history entries, like Plausible)
  useEffect(() => {
    // Skip initial mount: server already rendered with matching URL
    if (isFirstRender.current) {
      isFirstRender.current = false
      return
    }
    if (suppressNextPush.current) {
      suppressNextPush.current = false
      return
    }
    try {
      const params = mergeReportQueryParams(window.location.search, query)
      const qs = params.toString()
      const url = `${window.location.pathname}${qs ? `?${qs}` : ""}`
      if (nextHistoryModeRef.current === "replace") {
        window.history.replaceState({}, "", url)
      } else {
        window.history.pushState({}, "", url)
      }
      nextHistoryModeRef.current = "push"
    } catch (e) {
      // Non-fatal: log for debugging

      console.warn("Failed to update URL params for analytics query", e)
    }
  }, [query])

  const value = useMemo<QueryContextValue>(
    () => ({
      query,
      pathname,
      search,
      updateQuery,
    }),
    [pathname, query, search, updateQuery]
  )

  return <QueryContext.Provider value={value}>{children}</QueryContext.Provider>
}

// eslint-disable-next-line react-refresh/only-export-components
export function useQueryContext() {
  const context = useContext(QueryContext)
  if (!context) {
    throw new Error("useQueryContext must be used within a QueryProvider")
  }
  return context
}
