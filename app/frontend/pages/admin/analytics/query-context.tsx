import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  type ReactNode,
} from "react"

import { navigateAnalytics, useAnalyticsLocation } from "./lib/location-store"
import {
  mergeReportQueryParams,
  resolveInitialReportQuery,
} from "./lib/query-codec"
import { buildReportUrl, canonicalReportSearch } from "./lib/report-url"
import type { AnalyticsQuery } from "./types"

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

function parseLocationFromUrl(url: string | undefined) {
  if (!url) return { pathname: "", search: "" }

  const parsed = new URL(url, "http://analytics.test")
  return {
    pathname: parsed.pathname,
    search: parsed.search,
  }
}

export function QueryProvider({
  initialQuery,
  defaultQuery,
  initialUrl,
  children,
}: {
  initialQuery: AnalyticsQuery
  defaultQuery: AnalyticsQuery
  initialUrl?: string
  children: ReactNode
}) {
  const location = useAnalyticsLocation()
  const initialLocation = useMemo(
    () => parseLocationFromUrl(initialUrl),
    [initialUrl]
  )
  const pathname = location.pathname || initialLocation.pathname
  const search = location.search || initialLocation.search

  const query = useMemo(
    () =>
      resolveInitialReportQuery(
        search || undefined,
        initialQuery,
        defaultQuery
      ),
    [defaultQuery, initialQuery, search]
  )

  const updateQuery = useCallback(
    (
      updater: (current: AnalyticsQuery) => AnalyticsQuery,
      options?: { history?: "push" | "replace" }
    ) => {
      const next = updater(query)
      const nextUrl = buildReportUrl(
        pathname,
        mergeReportQueryParams(search, next)
      )
      const currentUrl = buildReportUrl(pathname, search)

      if (nextUrl === currentUrl) return

      navigateAnalytics(nextUrl, {
        history: options?.history ?? "push",
      })
    },
    [pathname, query, search]
  )

  useEffect(() => {
    if (typeof window === "undefined") return

    const current = window.location.search.replace(/^\?/, "")
    const canonical = canonicalReportSearch(window.location.search)
    if (canonical === current) return

    navigateAnalytics(buildReportUrl(window.location.pathname, canonical), {
      history: "replace",
    })
  }, [pathname, search])

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
