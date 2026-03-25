import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  type ReactNode,
} from "react"

import { mergeReportQueryParams, resolveInitialReportQuery } from "./api"
import { canonicalizeDashboardSearchParams } from "./lib/dashboard-url-state"
import { navigateAnalytics, useAnalyticsLocation } from "./lib/location-store"
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

export function QueryProvider({
  initialQuery,
  defaultQuery,
  children,
}: {
  initialQuery: AnalyticsQuery
  defaultQuery: AnalyticsQuery
  children: ReactNode
}) {
  const { pathname, search } = useAnalyticsLocation()
  const query = useMemo(
    () =>
      resolveInitialReportQuery(
        typeof window === "undefined" ? undefined : search,
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
      const nextSearch = mergeReportQueryParams(search, next).toString()
      const nextUrl = `${pathname}${nextSearch ? `?${nextSearch}` : ""}`
      const currentSearch = canonicalizeDashboardSearchParams(search).toString()
      const currentUrl = `${pathname}${currentSearch ? `?${currentSearch}` : ""}`

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
    const canonical = canonicalizeDashboardSearchParams(
      window.location.search
    ).toString()
    if (canonical === current) return

    navigateAnalytics(
      `${window.location.pathname}${canonical ? `?${canonical}` : ""}`,
      {
        history: "replace",
      }
    )
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
