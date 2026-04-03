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

import { getConsumer, type Subscription } from "@/lib/cable"

import { useAnalyticsHost } from "./host-context"
import { liveStatsChannelIdentifier } from "./live/live-stats-channel"
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
  liveSubscriptionToken,
  children,
}: {
  site: SiteContextValue
  initialTopStats: TopStatsPayload
  liveSubscriptionToken?: string | null
  children: ReactNode
}) {
  const { scopedPath, search } = useAnalyticsHost()
  const [topStats, setTopStats] = useState<TopStatsPayload>(initialTopStats)
  const [lastLoadedAt, setLastLoadedAt] = useState(() => Date.now())
  const resyncAbortRef = useRef<AbortController | null>(null)

  const touchLastLoaded = useCallback(() => setLastLoadedAt(Date.now()), [])

  const applyLiveVisitorsCount = useCallback((liveCount: number) => {
    setTopStats((prev) => {
      const index = prev.topStats.findIndex(
        (stat) => stat.graphMetric === "currentVisitors"
      )
      if (index < 0) return prev

      const currentStat = prev.topStats[index]
      if (!currentStat || currentStat.value === liveCount) return prev

      const nextTopStats = prev.topStats.slice()
      nextTopStats[index] = {
        ...currentStat,
        value: liveCount,
      }

      return {
        ...prev,
        topStats: nextTopStats,
      }
    })
  }, [])

  const resyncTopStats = useCallback(() => {
    resyncAbortRef.current?.abort()
    const controller = new AbortController()
    resyncAbortRef.current = controller

    fetch(`${scopedPath("/top_stats")}${search || ""}`, {
      headers: { Accept: "application/json" },
      signal: controller.signal,
    })
      .then(async (response) => {
        if (!response.ok) {
          throw new Error(
            `Top stats resync failed with status ${response.status}`
          )
        }

        const data = (await response.json()) as TopStatsPayload
        const liveCount = data.topStats.find(
          (stat) => stat.graphMetric === "currentVisitors"
        )?.value
        if (typeof liveCount !== "number") return

        applyLiveVisitorsCount(liveCount)
      })
      .catch((error) => {
        if (error.name !== "AbortError") {
          console.error(error)
        }
      })
  }, [applyLiveVisitorsCount, scopedPath, search])

  useEffect(() => {
    if (!liveSubscriptionToken) return

    const consumer = getConsumer()
    const subscription = consumer.subscriptions.create(
      liveStatsChannelIdentifier(liveSubscriptionToken),
      {
        connected: () => {
          if (
            typeof document === "undefined" ||
            document.visibilityState === "visible"
          ) {
            resyncTopStats()
          }
        },
        received: (data: { currentVisitors?: number }) => {
          if (typeof data.currentVisitors !== "number") return
          applyLiveVisitorsCount(data.currentVisitors)
        },
      }
    ) as Subscription

    return () => {
      resyncAbortRef.current?.abort()
      subscription.unsubscribe()
    }
  }, [applyLiveVisitorsCount, liveSubscriptionToken, resyncTopStats])

  useEffect(() => {
    if (!liveSubscriptionToken || typeof document === "undefined") return

    const handleVisibilityChange = () => {
      if (document.visibilityState === "visible") {
        resyncTopStats()
      }
    }

    document.addEventListener("visibilitychange", handleVisibilityChange)

    return () => {
      document.removeEventListener("visibilitychange", handleVisibilityChange)
      resyncAbortRef.current?.abort()
    }
  }, [liveSubscriptionToken, resyncTopStats])

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
