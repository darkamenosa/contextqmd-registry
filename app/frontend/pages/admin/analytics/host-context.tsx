import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  type ReactNode,
} from "react"

import {
  DEFAULT_ANALYTICS_REPORTS_PATH,
  resolveAdminAnalyticsReportsPath,
  resolveAdminAnalyticsScopePath,
} from "./lib/admin-analytics-host"
import type { DialogSegment } from "./lib/dialog-path"
import {
  baseAnalyticsPath,
  buildDialogPath as buildDialogPathForReports,
  buildReferrersPath as buildReferrersPathForReports,
} from "./lib/dialog-path"
import { buildReportUrl as buildReportUrlForPath } from "./lib/report-url"
import {
  AnalyticsLocationProvider,
  useAnalyticsLocationContext,
  type AnalyticsLocationAdapter,
  type AnalyticsNavigationOptions,
} from "./location-context"

export type AnalyticsHostAdapter = AnalyticsLocationAdapter & {
  resolveReportsPath?: (pathname: string) => string
  resolveScopePath?: (pathname: string) => string
}

export type AnalyticsHostContextValue = {
  pathname: string
  search: string
  reportsPath: string
  scopePath: string
  navigate: (url: string, options?: AnalyticsNavigationOptions) => void
  buildReportUrl: (search: URLSearchParams | string | undefined) => string
  scopedPath: (suffix: string) => string
  basePath: (qs?: string) => string
  buildDialogPath: (segment: DialogSegment, qs?: string) => string
  buildReferrersPath: (source: string, qs?: string) => string
  getDialogSearch: () => string
  openDialogRoute: (pathBuilder: (qs: string) => string) => void
  syncDialogRoute: (open: boolean, pathBuilder: (qs: string) => string) => void
  closeDialogRoute: () => void
}

const AnalyticsHostContext = createContext<AnalyticsHostContextValue | null>(
  null
)

function normalizeScopedSuffix(suffix: string) {
  return suffix.startsWith("/") ? suffix : `/${suffix}`
}

export function AnalyticsHostProvider({
  initialUrl,
  adapter,
  children,
}: {
  initialUrl?: string
  adapter?: AnalyticsHostAdapter
  children: ReactNode
}) {
  return (
    <AnalyticsLocationProvider initialUrl={initialUrl} adapter={adapter}>
      <AnalyticsHostBoundary adapter={adapter}>
        {children}
      </AnalyticsHostBoundary>
    </AnalyticsLocationProvider>
  )
}

function AnalyticsHostBoundary({
  adapter,
  children,
}: {
  adapter?: AnalyticsHostAdapter
  children: ReactNode
}) {
  const { pathname, search, navigate } = useAnalyticsLocationContext()
  const resolvedAdapter = adapter ?? {}
  const resolveReportsPath =
    resolvedAdapter.resolveReportsPath ?? resolveAdminAnalyticsReportsPath
  const resolveScopePath =
    resolvedAdapter.resolveScopePath ?? resolveAdminAnalyticsScopePath
  const effectivePathname = pathname || DEFAULT_ANALYTICS_REPORTS_PATH
  const reportsPath = resolveReportsPath(effectivePathname)
  const scopePath = resolveScopePath(effectivePathname)

  const buildReportUrl = useCallback(
    (nextSearch: URLSearchParams | string | undefined) =>
      buildReportUrlForPath(effectivePathname, nextSearch),
    [effectivePathname]
  )

  const scopedPath = useCallback(
    (suffix: string) => `${scopePath}${normalizeScopedSuffix(suffix)}`,
    [scopePath]
  )

  const basePath = useCallback(
    (qs = "") => baseAnalyticsPath(qs, reportsPath),
    [reportsPath]
  )

  const buildDialogPath = useCallback(
    (segment: DialogSegment, qs = "") =>
      buildDialogPathForReports(segment, qs, reportsPath),
    [reportsPath]
  )

  const buildReferrersPath = useCallback(
    (source: string, qs = "") =>
      buildReferrersPathForReports(source, qs, reportsPath),
    [reportsPath]
  )

  const getDialogSearch = useCallback(() => {
    const params = new URLSearchParams(search)
    params.delete("dialog")
    return params.toString()
  }, [search])

  const openDialogRoute = useCallback(
    (pathBuilder: (qs: string) => string) => {
      navigate(pathBuilder(getDialogSearch()))
    },
    [getDialogSearch, navigate]
  )

  const syncDialogRoute = useCallback(
    (open: boolean, pathBuilder: (qs: string) => string) => {
      const dialogSearch = getDialogSearch()
      navigate(open ? pathBuilder(dialogSearch) : basePath(dialogSearch))
    },
    [basePath, getDialogSearch, navigate]
  )

  const closeDialogRoute = useCallback(() => {
    navigate(basePath(getDialogSearch()))
  }, [basePath, getDialogSearch, navigate])

  const value = useMemo<AnalyticsHostContextValue>(
    () => ({
      pathname: effectivePathname,
      search,
      reportsPath,
      scopePath,
      navigate,
      buildReportUrl,
      scopedPath,
      basePath,
      buildDialogPath,
      buildReferrersPath,
      getDialogSearch,
      openDialogRoute,
      syncDialogRoute,
      closeDialogRoute,
    }),
    [
      basePath,
      buildDialogPath,
      buildReferrersPath,
      buildReportUrl,
      closeDialogRoute,
      getDialogSearch,
      navigate,
      openDialogRoute,
      effectivePathname,
      reportsPath,
      scopePath,
      scopedPath,
      search,
      syncDialogRoute,
    ]
  )

  return (
    <AnalyticsHostContext.Provider value={value}>
      {children}
    </AnalyticsHostContext.Provider>
  )
}

// eslint-disable-next-line react-refresh/only-export-components
export function useAnalyticsHost() {
  const context = useContext(AnalyticsHostContext)
  if (!context) {
    throw new Error(
      "useAnalyticsHost must be used within an AnalyticsHostProvider"
    )
  }
  return context
}
