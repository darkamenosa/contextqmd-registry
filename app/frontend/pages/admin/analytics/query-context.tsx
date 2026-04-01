import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  type ReactNode,
} from "react"

import { useAnalyticsHost } from "./host-context"
import {
  mergeReportQueryParams,
  resolveInitialReportQuery,
} from "./lib/query-codec"
import { canonicalReportSearch } from "./lib/report-url"
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
  const { pathname, search, buildReportUrl, navigate } = useAnalyticsHost()

  const query = useMemo(
    () => resolveInitialReportQuery(search, initialQuery, defaultQuery),
    [defaultQuery, initialQuery, search]
  )

  const updateQuery = useCallback(
    (
      updater: (current: AnalyticsQuery) => AnalyticsQuery,
      options?: { history?: "push" | "replace" }
    ) => {
      const next = updater(query)
      const nextUrl = buildReportUrl(mergeReportQueryParams(search, next))
      const currentUrl = buildReportUrl(search)

      if (nextUrl === currentUrl) return

      navigate(nextUrl, {
        history: options?.history ?? "push",
      })
    },
    [buildReportUrl, navigate, query, search]
  )

  useEffect(() => {
    const current = search.replace(/^\?/, "")
    const canonical = canonicalReportSearch(search)
    if (canonical === current) return

    navigate(buildReportUrl(canonical), {
      history: "replace",
    })
  }, [buildReportUrl, navigate, search])

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
