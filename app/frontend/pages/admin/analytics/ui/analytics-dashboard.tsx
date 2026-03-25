import { useEffect, useMemo, useRef, useState } from "react"
import { AlertCircle } from "lucide-react"

import { Button } from "@/components/ui/button"
import { Skeleton } from "@/components/ui/skeleton"

import {
  fetchBehaviors,
  fetchDevices,
  fetchLocations,
  fetchMainGraph,
  fetchPages,
  fetchSources,
  fetchTopStats,
} from "../api"
import {
  getBehaviorsFunnelFromSearch,
  getBehaviorsPropertyFromSearch,
  getGraphIntervalFromSearch,
  getGraphMetricFromSearch,
} from "../lib/dashboard-url-state"
import {
  devicesModeForSegment,
  locationsModeForSegment,
  modeForSegment,
  pagesModeForSegment,
  parseDialogFromPath,
} from "../lib/dialog-path"
import {
  BEHAVIORS_MODES,
  DEVICES_MODES,
  getBehaviorsModeFromSearch,
  getDevicesModeFromSearch,
  getLocationsModeFromSearch,
  getPagesModeFromSearch,
  getSourcesModeFromSearch,
  inferDevicesModeFromFilters,
  LOCATIONS_MODES,
  PAGES_MODES,
  readStoredMode,
  SOURCES_MODES,
} from "../lib/panel-mode"
import { useQueryContext } from "../query-context"
import { useSiteContext } from "../site-context"
import { TopStatsProvider } from "../top-stats-context"
import type {
  BehaviorsPayload,
  DevicesPayload,
  ListPayload,
  MainGraphPayload,
  MapPayload,
  TopStatsPayload,
} from "../types"
import BehaviorsPanel from "./behaviors-panel"
import DevicesPanel from "./devices-panel"
import LocationsPanel from "./locations-panel"
import PagesPanel from "./pages-panel"
import SourcesPanel from "./sources-panel"
import TopBar from "./top-bar"
import VisitorGraph from "./visitor-graph"

type DashboardBootPayload = {
  topStats: TopStatsPayload
  mainGraph: MainGraphPayload
  sources: ListPayload
  pages: ListPayload
  locations: MapPayload | ListPayload
  devices: DevicesPayload
  behaviors: BehaviorsPayload | null
}

const STORAGE_PREFIXES = {
  sources: "admin.analytics.sources",
  pages: "admin.analytics.pages",
  locations: "admin.analytics.locations",
  devices: "admin.analytics.devices",
  behaviors: "admin.analytics.behaviors",
} as const

export default function AnalyticsDashboard() {
  const { pathname, query, search } = useQueryContext()
  const site = useSiteContext()
  const isRealtime = useMemo(() => query.period === "realtime", [query.period])
  const hasBehaviors =
    site.hasGoals || site.funnelsAvailable || site.propsAvailable
  const initialQueryRef = useRef(query)
  const initialPathnameRef = useRef(pathname)
  const initialSearchRef = useRef(search)
  const [boot, setBoot] = useState<DashboardBootPayload | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)
  const [reloadKey, setReloadKey] = useState(0)

  useEffect(() => {
    const controller = new AbortController()

    async function load() {
      setLoading(true)
      setError(null)

      try {
        const bootQuery = initialQueryRef.current
        const initialSearch = initialSearchRef.current
        const parsedDialog = parseDialogFromPath(initialPathnameRef.current)
        const storedSourcesMode = readStoredMode(
          `${STORAGE_PREFIXES.sources}.${site.domain}`,
          SOURCES_MODES
        )
        const storedPagesMode = readStoredMode(
          `${STORAGE_PREFIXES.pages}.${site.domain}`,
          PAGES_MODES
        )
        const storedLocationsMode = readStoredMode(
          `${STORAGE_PREFIXES.locations}.${site.domain}`,
          LOCATIONS_MODES
        )
        const storedDevicesMode = readStoredMode(
          `${STORAGE_PREFIXES.devices}.${site.domain}`,
          DEVICES_MODES
        )
        const storedBehaviorsMode = readStoredMode(
          `${STORAGE_PREFIXES.behaviors}.${site.domain}`,
          site.hasGoals
            ? BEHAVIORS_MODES
            : BEHAVIORS_MODES.filter((value) => value !== "conversions")
        )
        const sourcesMode =
          parsedDialog.type === "referrers"
            ? "all"
            : parsedDialog.type === "segment"
              ? (modeForSegment(parsedDialog.segment) ??
                getSourcesModeFromSearch(initialSearch, bootQuery))
              : (getSourcesModeFromSearch(initialSearch, bootQuery) ??
                storedSourcesMode ??
                "all")
        const pagesMode =
          parsedDialog.type === "segment"
            ? (pagesModeForSegment(parsedDialog.segment) ??
              getPagesModeFromSearch(initialSearch, bootQuery.mode) ??
              storedPagesMode ??
              "pages")
            : (getPagesModeFromSearch(initialSearch, bootQuery.mode) ??
              storedPagesMode ??
              "pages")
        const locationsMode =
          parsedDialog.type === "segment"
            ? (locationsModeForSegment(parsedDialog.segment) ??
              getLocationsModeFromSearch(initialSearch, bootQuery.mode) ??
              storedLocationsMode ??
              "map")
            : (getLocationsModeFromSearch(initialSearch, bootQuery.mode) ??
              storedLocationsMode ??
              "map")
        const devicesMode = inferDevicesModeFromFilters(
          parsedDialog.type === "segment"
            ? (devicesModeForSegment(parsedDialog.segment) ??
                getDevicesModeFromSearch(initialSearch, bootQuery.mode) ??
                storedDevicesMode ??
                "browsers")
            : (getDevicesModeFromSearch(initialSearch, bootQuery.mode) ??
                storedDevicesMode ??
                "browsers"),
          bootQuery.filters
        )
        const topStats = await fetchTopStats(bootQuery, controller.signal)
        const requestedGraphMetric = getGraphMetricFromSearch(initialSearch)
        const graphMetric =
          requestedGraphMetric &&
          topStats.graphableMetrics.includes(requestedGraphMetric)
            ? requestedGraphMetric
            : (topStats.graphableMetrics[0] ?? "visitors")
        const requestedGraphInterval = getGraphIntervalFromSearch(initialSearch)
        const graphInterval = requestedGraphInterval || topStats.interval
        const behaviorsMode =
          parsedDialog.type === "segment" &&
          parsedDialog.segment === "behaviors"
            ? (getBehaviorsModeFromSearch(
                initialSearch,
                bootQuery.mode,
                site.hasGoals
              ) ??
              storedBehaviorsMode ??
              (site.hasGoals
                ? "conversions"
                : site.propsAvailable
                  ? "props"
                  : site.funnelsAvailable
                    ? "funnels"
                    : undefined))
            : (storedBehaviorsMode ??
              (site.hasGoals
                ? "conversions"
                : site.propsAvailable
                  ? "props"
                  : site.funnelsAvailable
                    ? "funnels"
                    : undefined))
        const behaviorsFunnel =
          parsedDialog.type === "segment" &&
          parsedDialog.segment === "behaviors"
            ? getBehaviorsFunnelFromSearch(initialSearch, bootQuery.funnel)
            : null
        const behaviorsProperty =
          parsedDialog.type === "segment" &&
          parsedDialog.segment === "behaviors"
            ? getBehaviorsPropertyFromSearch(initialSearch)
            : null

        const [mainGraph, sources, pages, locations, devices, behaviors] =
          await Promise.all([
            fetchMainGraph(
              bootQuery,
              { metric: graphMetric, interval: graphInterval },
              controller.signal
            ),
            fetchSources(
              bootQuery,
              { mode: sourcesMode ?? "all" },
              controller.signal
            ),
            fetchPages(bootQuery, { mode: pagesMode }, controller.signal),
            fetchLocations(
              bootQuery,
              { mode: locationsMode },
              controller.signal
            ),
            fetchDevices(bootQuery, { mode: devicesMode }, controller.signal),
            hasBehaviors
              ? fetchBehaviors(
                  bootQuery,
                  {
                    mode: behaviorsMode,
                    funnel: behaviorsFunnel ?? undefined,
                    property:
                      behaviorsMode === "props"
                        ? (behaviorsProperty ?? undefined)
                        : undefined,
                  },
                  controller.signal
                )
              : Promise.resolve(null),
          ])

        setBoot({
          topStats,
          mainGraph,
          sources,
          pages,
          locations,
          devices,
          behaviors,
        })
      } catch (nextError) {
        if ((nextError as Error).name === "AbortError") return
        setError("Failed to load analytics dashboard data.")
      } finally {
        if (!controller.signal.aborted) {
          setLoading(false)
        }
      }
    }

    void load()

    return () => controller.abort()
  }, [
    hasBehaviors,
    reloadKey,
    site.domain,
    site.funnelsAvailable,
    site.hasGoals,
    site.propsAvailable,
  ])

  if (loading && !boot) {
    return <AnalyticsSkeleton />
  }

  if (error && !boot) {
    return (
      <div className="flex min-h-[24rem] flex-col items-center justify-center gap-4 rounded-lg border border-border bg-card p-6 text-center">
        <AlertCircle className="size-6 text-muted-foreground" />
        <div className="space-y-1">
          <p className="text-sm font-medium text-foreground">{error}</p>
          <p className="text-sm text-muted-foreground">
            The analytics shell loads data client-side now. Retry to refetch the
            initial dashboard payloads.
          </p>
        </div>
        <Button onClick={() => setReloadKey((current) => current + 1)}>
          Retry
        </Button>
      </div>
    )
  }

  if (!boot) return null

  return (
    <TopStatsProvider initial={boot.topStats}>
      <div className="flex flex-col gap-4">
        <TopBar showCurrentVisitors={!isRealtime} />

        <VisitorGraph initialGraph={boot.mainGraph} />

        <section className="grid gap-4 lg:grid-cols-2">
          <SourcesPanel initialData={boot.sources} />
          <PagesPanel initialData={boot.pages} />
        </section>

        <section className="grid gap-4 lg:grid-cols-2">
          <LocationsPanel initialData={boot.locations} />
          <DevicesPanel initialData={boot.devices} />
        </section>

        {hasBehaviors && boot.behaviors ? (
          <BehaviorsPanel initialData={boot.behaviors} />
        ) : null}
      </div>
    </TopStatsProvider>
  )
}

function AnalyticsSkeleton() {
  return (
    <div className="flex flex-col gap-4">
      {/* Top bar skeleton */}
      <div className="flex items-center justify-between">
        <Skeleton className="h-8 w-36 rounded-full" />
        <div className="flex gap-2">
          <Skeleton className="h-7 w-20 rounded-lg" />
          <Skeleton className="h-7 w-28 rounded-lg" />
        </div>
      </div>

      {/* Stats + chart skeleton */}
      <div className="rounded-lg border border-border bg-card p-4">
        <div className="flex gap-1 border-b border-border pb-3">
          {Array.from({ length: 6 }).map((_, i) => (
            <div key={i} className="flex flex-1 flex-col gap-1.5 px-3 py-2">
              <Skeleton className="h-3 w-20" />
              <Skeleton className="h-5 w-12" />
              <Skeleton className="h-3 w-10" />
            </div>
          ))}
        </div>
        <div className="pt-4">
          <Skeleton className="h-56 w-full rounded-sm" />
        </div>
      </div>

      {/* Panels skeleton */}
      <div className="grid gap-4 lg:grid-cols-2">
        <PanelSkeleton title="Top Sources" rows={3} />
        <PanelSkeleton title="Top Pages" rows={3} />
      </div>
      <div className="grid gap-4 lg:grid-cols-2">
        <PanelSkeleton title="Countries" rows={2} />
        <PanelSkeleton title="Devices" rows={2} />
      </div>
    </div>
  )
}

function PanelSkeleton({ title, rows }: { title: string; rows: number }) {
  return (
    <div className="rounded-lg border border-border bg-card p-4">
      <div className="flex items-center justify-between pb-3">
        <span className="text-base font-medium">{title}</span>
        <Skeleton className="h-4 w-32" />
      </div>
      <div className="space-y-3">
        {Array.from({ length: rows }).map((_, i) => (
          <div key={i} className="flex items-center justify-between">
            <Skeleton className="h-4 w-2/3" />
            <Skeleton className="h-4 w-8" />
          </div>
        ))}
      </div>
    </div>
  )
}
