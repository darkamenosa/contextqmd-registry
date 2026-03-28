import {
  createContext,
  useCallback,
  useContext,
  useMemo,
  useState,
  type ReactNode,
} from "react"

import type { SiteContextValue, TopStatsPayload } from "./types"

export type AnalyticsDashboardContextValue = {
  site: SiteContextValue
  topStats: TopStatsPayload
  updateTopStats: (payload: TopStatsPayload) => void
  lastLoadedAt: number
  touchLastLoaded: () => void
}

const AnalyticsDashboardContext =
  createContext<AnalyticsDashboardContextValue | null>(null)

export function AnalyticsDashboardProvider({
  site,
  initialTopStats,
  children,
}: {
  site: SiteContextValue
  initialTopStats: TopStatsPayload
  children: ReactNode
}) {
  const [topStats, setTopStats] = useState<TopStatsPayload>(initialTopStats)
  const [lastLoadedAt, setLastLoadedAt] = useState(() => Date.now())

  const touchLastLoaded = useCallback(() => setLastLoadedAt(Date.now()), [])

  const value = useMemo<AnalyticsDashboardContextValue>(
    () => ({
      site,
      topStats,
      updateTopStats: setTopStats,
      lastLoadedAt,
      touchLastLoaded,
    }),
    [lastLoadedAt, site, topStats, touchLastLoaded]
  )

  return (
    <AnalyticsDashboardContext.Provider value={value}>
      {children}
    </AnalyticsDashboardContext.Provider>
  )
}

// eslint-disable-next-line react-refresh/only-export-components
export function useAnalyticsDashboardContext() {
  const context = useContext(AnalyticsDashboardContext)
  if (!context) {
    throw new Error(
      "useAnalyticsDashboardContext must be used within an AnalyticsDashboardProvider"
    )
  }
  return context
}
