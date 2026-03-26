import {
  startTransition,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react"

import { useClientComponent } from "@/hooks/use-client-component"

import { fetchLocations } from "../api"
import { flagFromIso2 } from "../lib/country-flag"
import {
  baseAnalyticsPath,
  buildDialogPath,
  locationsModeForSegment,
  locationsSegmentForMode,
  parseDialogFromPath,
} from "../lib/dialog-path"
import { navigateAnalytics } from "../lib/location-store"
import { getLocationsModeAfterFilterChange } from "../lib/panel-mode"
import { useScopedQuery } from "../lib/query-scope"
import { useQueryContext } from "../query-context"
import { useSiteContext } from "../site-context"
import type {
  AnalyticsQuery,
  ListItem,
  ListMetricKey,
  ListPayload,
  MapPayload,
} from "../types"
import DetailsButton from "./details-button"
import { MetricTable, PanelEmptyState, PanelListSkeleton } from "./list-table"
import { PanelTab, PanelTabs } from "./panel-tabs"
import RemoteDetailsDialog from "./remote-details-dialog"

const LOCATION_TABS: Array<{ value: string; label: string }> = [
  { value: "map", label: "Map" },
  { value: "countries", label: "Countries" },
  { value: "regions", label: "Regions" },
  { value: "cities", label: "Cities" },
]

const STORAGE_PREFIX = "admin.analytics.locations"

const loadCountriesMapComponent = () =>
  import("./countries-map").then(({ default: component }) => component)

type LocationsPanelProps = {
  initialData: MapPayload | ListPayload
  initialMode: string
}

type PanelData =
  | {
      type: "map"
      payload: MapPayload
    }
  | {
      type: "list"
      payload: ListPayload
    }

export default function LocationsPanel({
  initialData,
  initialMode,
}: LocationsPanelProps) {
  const { query, pathname, updateQuery } = useQueryContext()
  const site = useSiteContext()

  const [preferredMode, setPreferredMode] = useState(() => initialMode)
  const [data, setData] = useState<PanelData>(() =>
    "map" in initialData
      ? { type: "map", payload: initialData as MapPayload }
      : { type: "list", payload: initialData as ListPayload }
  )
  const [loading, setLoading] = useState(false)
  const { value: baseQuery } = useScopedQuery(query, {
    omitMode: true,
    omitMetric: true,
    omitInterval: true,
  })
  const dialogMode = useMemo(() => {
    const parsed = parseDialogFromPath(pathname)
    if (parsed.type !== "segment") return null
    return locationsModeForSegment(parsed.segment)
  }, [pathname])
  const mode = dialogMode ?? preferredMode
  const { Component: CountriesMapComponent } = useClientComponent(
    loadCountriesMapComponent,
    { preload: mode === "map" }
  )
  const detailsOpen = Boolean(dialogMode)
  const initialRequestKey = useMemo(
    () => JSON.stringify([baseQuery, initialMode]),
    [baseQuery, initialMode]
  )
  const requestKey = useMemo(
    () => JSON.stringify([baseQuery, mode]),
    [baseQuery, mode]
  )
  const lastRequestKeyRef = useRef(initialRequestKey)
  const previousFiltersRef = useRef(query.filters)
  const countriesRestoreModeRef = useRef<"map" | "countries">("countries")

  const closeDetailsDialog = useCallback(() => {
    try {
      const sp = new URLSearchParams(window.location.search)
      sp.delete("dialog")
      navigateAnalytics(baseAnalyticsPath(sp.toString()))
    } catch {
      // Ignore history errors; local dialog state still works.
    }
  }, [])

  useEffect(() => {
    if (requestKey === lastRequestKeyRef.current) return
    lastRequestKeyRef.current = requestKey

    const controller = new AbortController()
    startTransition(() => setLoading(true))
    fetchLocations(baseQuery, { mode }, controller.signal)
      .then((result) => {
        if ("map" in result) {
          setData({ type: "map", payload: result as MapPayload })
        } else {
          setData({ type: "list", payload: result as ListPayload })
        }
      })
      .catch((error) => {
        if (error.name !== "AbortError") console.error(error)
      })
      .finally(() => setLoading(false))

    return () => controller.abort()
  }, [baseQuery, mode, requestKey])

  useEffect(() => {
    const nextMode = getLocationsModeAfterFilterChange(
      mode,
      previousFiltersRef.current,
      query.filters,
      countriesRestoreModeRef.current
    )
    previousFiltersRef.current = query.filters

    if (!nextMode || nextMode === mode) return

    setPreferredMode(nextMode)
    if (typeof window !== "undefined") {
      localStorage.setItem(`${STORAGE_PREFIX}.${site.domain}`, nextMode)
    }
  }, [mode, query.filters, site.domain])

  const highlightMetric = useMemo(() => {
    if (data.type === "list") {
      return data.payload.metrics.includes("visitors")
        ? "visitors"
        : data.payload.metrics[0]
    }
    return "visitors"
  }, [data])

  const activeTitle = useMemo(() => {
    switch (mode) {
      case "regions":
        return "Regions"
      case "cities":
        return "Cities"
      case "countries":
      case "map":
      default:
        return "Countries"
    }
  }, [mode])

  const firstColumnLabel = useMemo(() => {
    switch (mode) {
      case "regions":
        return "Region"
      case "cities":
        return "City"
      default:
        return "Country"
    }
  }, [mode])

  // Render a country flag for region/city rows when a country filter is active.
  // We intentionally do not attempt per-row geocoding; if no country filter,
  // we omit the flag for regions/cities.
  const renderRegionCityFlag = useCallback(
    (item: ListItem) => {
      // Prefer explicit countryFlag provided by backend (parity with Plausible)
      const explicit = item.countryFlag as string | undefined
      if (explicit && typeof explicit === "string" && explicit.length <= 6) {
        return <span aria-hidden>{explicit}</span>
      }
      const candidate = String(
        (query.filters && query.filters.country) ||
          item.country ||
          item.alpha2 ||
          item.code ||
          ""
      )
      const flag = flagFromIso2(candidate)
      return flag ? <span aria-hidden>{flag}</span> : null
    },
    [query.filters]
  )

  // Details view now uses a remote modal; build-time list payload no longer needed

  // Limit card view to top 9 only for list modes; keep map view unchanged
  const limitedListPayload = useMemo(() => {
    if (data.type !== "list") return null
    const metricKey = data.payload.metrics[0] ?? "visitors"
    const sorted = [...data.payload.results].sort((a, b) => {
      const av = Number(a[metricKey] ?? 0)
      const bv = Number(b[metricKey] ?? 0)
      if (av === bv) return String(a.name).localeCompare(String(b.name))
      return bv - av
    })
    const sliced = sorted.slice(0, 9)
    return {
      ...data.payload,
      metrics: pickCardMetrics(data.payload.metrics),
      results: sliced,
      meta: { ...data.payload.meta, hasMore: data.payload.results.length > 9 },
    }
  }, [data])

  const handleCountrySelect = useCallback(
    (countryCode: string, countryLabel?: string) => {
      countriesRestoreModeRef.current = mode === "map" ? "map" : "countries"
      updateQuery((current) => {
        const next: AnalyticsQuery = {
          ...current,
          filters: { ...current.filters, country: countryCode },
        }
        if (countryLabel && countryLabel !== countryCode) {
          next.labels = { ...(current.labels || {}), country: countryLabel }
        }
        return next
      })
      setPreferredMode("regions")
      closeDetailsDialog()
      if (typeof window !== "undefined") {
        localStorage.setItem(`${STORAGE_PREFIX}.${site.domain}`, "regions")
      }
    },
    [closeDetailsDialog, mode, site.domain, updateQuery]
  )

  const handleRegionSelect = useCallback(
    (regionCode: string, regionLabel?: string) => {
      updateQuery((current) => {
        const next: AnalyticsQuery = {
          ...current,
          filters: { ...current.filters, region: regionCode },
        }
        if (regionLabel && regionLabel !== regionCode) {
          next.labels = { ...(current.labels || {}), region: regionLabel }
        }
        return next
      })
      setPreferredMode("cities")
      closeDetailsDialog()
      if (typeof window !== "undefined") {
        localStorage.setItem(`${STORAGE_PREFIX}.${site.domain}`, "cities")
      }
    },
    [closeDetailsDialog, site.domain, updateQuery]
  )

  const onDetailsRowClick = useCallback(
    (item: ListItem) => {
      if (mode === "regions") {
        handleRegionSelect(String(item.code ?? item.name), String(item.name))
      } else if (mode === "countries" || mode === "map") {
        handleCountrySelect(String(item.code ?? item.name), String(item.name))
      }
    },
    [handleCountrySelect, handleRegionSelect, mode]
  )

  return (
    <section
      className={`flex flex-col ${mode === "map" ? "gap-0" : "gap-3"} rounded-lg border border-border bg-card p-4`}
      data-testid="locations-panel"
    >
      <header className="flex flex-wrap items-center justify-between gap-3">
        <h2 className="text-base font-medium">{activeTitle}</h2>
        <PanelTabs>
          {LOCATION_TABS.map((tab) => (
            <PanelTab
              key={tab.value}
              active={mode === tab.value}
              onClick={() => {
                setPreferredMode(tab.value)
                if (typeof window !== "undefined") {
                  localStorage.setItem(
                    `${STORAGE_PREFIX}.${site.domain}`,
                    tab.value
                  )
                }
              }}
            >
              {tab.label}
            </PanelTab>
          ))}
        </PanelTabs>
      </header>

      {loading ? (
        <PanelListSkeleton firstColumnLabel={firstColumnLabel} />
      ) : data.type === "map" ? (
        <>
          {CountriesMapComponent ? (
            <CountriesMapComponent
              data={data.payload}
              onSelectCountry={handleCountrySelect}
            />
          ) : (
            <CountriesMapFallback />
          )}
          <div className="flex justify-center pt-0">
            <DetailsButton
              onClick={() => {
                try {
                  const sp = new URLSearchParams(window.location.search)
                  sp.delete("dialog")
                  const seg = locationsSegmentForMode(
                    mode as "map" | "countries" | "regions" | "cities"
                  )
                  navigateAnalytics(buildDialogPath(seg, sp.toString()))
                } catch {
                  // Ignore history errors when opening details.
                }
              }}
            >
              Details
            </DetailsButton>
          </div>
        </>
      ) : (
        <>
          {data.payload.results.length === 0 ? (
            <PanelEmptyState />
          ) : (
            <MetricTable
              data={
                limitedListPayload ??
                (data as Extract<PanelData, { type: "list" }>).payload
              }
              highlightedMetric={highlightMetric ?? "visitors"}
              onRowClick={(item) => {
                if (mode === "regions") {
                  handleRegionSelect(
                    String(item.code ?? item.name),
                    String(item.name)
                  )
                } else if (mode === "countries") {
                  handleCountrySelect(
                    String(item.code ?? item.name),
                    String(item.name)
                  )
                } else if (mode === "cities") {
                  updateQuery((current) => ({
                    ...current,
                    filters: { ...current.filters, city: String(item.name) },
                    labels: {
                      ...(current.labels || {}),
                      city: String(item.name),
                    },
                  }))
                }
              }}
              renderLeading={
                mode === "regions" || mode === "cities"
                  ? renderRegionCityFlag
                  : undefined
              }
              displayBars={false}
              firstColumnLabel={firstColumnLabel}
              barColorTheme="cyan"
              testId="locations"
            />
          )}
          <div className="mt-auto flex justify-center pt-3">
            <DetailsButton
              data-testid="locations-details-btn"
              onClick={() => {
                try {
                  const sp = new URLSearchParams(window.location.search)
                  sp.delete("dialog")
                  const seg = locationsSegmentForMode(
                    mode as "map" | "countries" | "regions" | "cities"
                  )
                  navigateAnalytics(buildDialogPath(seg, sp.toString()))
                } catch {
                  // Ignore history errors when opening details.
                }
              }}
            >
              Details
            </DetailsButton>
          </div>
        </>
      )}

      {
        <RemoteDetailsDialog
          open={detailsOpen}
          onOpenChange={(open) => {
            try {
              const sp = new URLSearchParams(window.location.search)
              sp.delete("dialog")
              const qs = sp.toString()
              if (open) {
                const seg = locationsSegmentForMode(
                  mode as "map" | "countries" | "regions" | "cities"
                )
                navigateAnalytics(buildDialogPath(seg, qs))
              } else {
                navigateAnalytics(baseAnalyticsPath(qs))
              }
            } catch {
              // Ignore history errors when syncing modal state.
            }
          }}
          title={`Top ${activeTitle}`}
          endpoint={"/admin/analytics/locations"}
          extras={{ mode: mode === "map" ? "countries" : mode }}
          firstColumnLabel={firstColumnLabel}
          renderLeading={
            mode === "regions" || mode === "cities"
              ? renderRegionCityFlag
              : undefined
          }
          defaultSortKey={"visitors"}
          onRowClick={(item) => {
            if (mode === "cities") {
              updateQuery((current) => {
                const cityName = String(item.name)
                const next: AnalyticsQuery = {
                  ...current,
                  filters: { ...current.filters, city: cityName },
                }
                if (current.labels?.city !== cityName) {
                  next.labels = { ...(current.labels || {}), city: cityName }
                }
                return next
              })
              closeDetailsDialog()
            } else {
              onDetailsRowClick(item)
            }
          }}
        />
      }
    </section>
  )
}

function pickCardMetrics(metrics: ListMetricKey[]): ListMetricKey[] {
  const preferred: ListMetricKey[] = []
  if (metrics.includes("visitors")) preferred.push("visitors")
  if (metrics.includes("percentage")) preferred.push("percentage")
  else if (metrics.includes("conversionRate")) preferred.push("conversionRate")
  return preferred.length > 0 ? preferred : metrics.slice(0, 2)
}

function CountriesMapFallback() {
  return (
    <div className="overflow-hidden rounded-xs border border-border/70 bg-card">
      <div className="aspect-[5/4] w-full animate-pulse bg-muted/55" />
      <div className="flex items-center justify-between border-t border-border/60 px-3 py-2.5">
        <div className="h-3 w-24 rounded bg-muted/70" />
        <div className="h-3 w-40 rounded bg-muted/70" />
      </div>
    </div>
  )
}
