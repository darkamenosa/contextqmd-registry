import {
  startTransition,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react"
import worldTopology from "@/data/countries-110m.json"
import { geoMercator, geoPath } from "d3-geo"
import { feature } from "topojson-client"

import { fetchLocations } from "../api"
import {
  baseAnalyticsPath,
  buildDialogPath,
  locationsModeForSegment,
  locationsSegmentForMode,
  parseDialogFromPath,
} from "../lib/dialog-path"
import { numberShortFormatter } from "../lib/number-formatter"
import {
  getLocationsModeFromSearch,
  hasPanelModeSearchParam,
  LOCATIONS_MODES,
  readStoredMode,
  setPanelModeSearchParam,
  syncPanelModeInUrl,
} from "../lib/panel-mode"
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
import { MetricTable } from "./list-table"
import { PanelTab, PanelTabs } from "./panel-tabs"
import RemoteDetailsDialog from "./remote-details-dialog"

const LOCATION_TABS: Array<{ value: string; label: string }> = [
  { value: "map", label: "Map" },
  { value: "countries", label: "Countries" },
  { value: "regions", label: "Regions" },
  { value: "cities", label: "Cities" },
]

const STORAGE_PREFIX = "admin.analytics.locations"
// Vendored TopoJSON to avoid CDN/network issues in dashboards
// Source: https://cdn.jsdelivr.net/npm/world-atlas@2/countries-110m.json
const MAP_WIDTH = 720
// Taller intrinsic viewBox so the SVG grows more vertically relative to its width
const MAP_HEIGHT = 576 // 5:4 aspect vs old 2:1
const MAP_MARGIN_X = 12 // horizontal breathing room
const MAP_MARGIN_Y = 0 // remove vertical padding to maximize map height
const MAP_COLOR_STOPS = [
  "#d6eef8",
  "#a0d8ef",
  "#6ec2e6",
  "#45a5d4",
  "#2b7da8",
] as const
const MAP_IDLE_FILL =
  "color-mix(in oklch, var(--muted) 82%, var(--background) 18%)"
const MAP_IDLE_STROKE =
  "color-mix(in oklch, var(--border) 82%, var(--foreground) 18%)"
const MAP_ACTIVE_STROKE = "#6ec2e6"

type LocationsPanelProps = {
  initialData: MapPayload | ListPayload
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

export default function LocationsPanel({ initialData }: LocationsPanelProps) {
  const { query, pathname, search, updateQuery } = useQueryContext()
  const site = useSiteContext()
  const initialMode = getLocationsModeFromSearch(search, query.mode) ?? "map"

  const [preferredMode, setPreferredMode] = useState(
    () =>
      readStoredMode(`${STORAGE_PREFIX}.${site.domain}`, LOCATIONS_MODES) ??
      "map"
  )
  const [data, setData] = useState<PanelData>(() =>
    "map" in initialData
      ? { type: "map", payload: initialData as MapPayload }
      : { type: "list", payload: initialData as ListPayload }
  )
  const [loading, setLoading] = useState(false)
  const queryMode = getLocationsModeFromSearch(search, query.mode)
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
  const hasExplicitModeParam = useMemo(
    () => hasPanelModeSearchParam(search, "locations"),
    [search]
  )
  const mode = dialogMode ?? queryMode ?? preferredMode
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

  const closeDetailsDialog = useCallback(() => {
    try {
      const sp = new URLSearchParams(window.location.search)
      sp.delete("dialog")
      setPanelModeSearchParam(sp, "locations", mode)
      window.history.pushState({}, "", baseAnalyticsPath(sp.toString()))
    } catch {
      // Ignore history errors; local dialog state still works.
    }
  }, [mode])

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
    if (dialogMode || hasExplicitModeParam) return
    if (mode === "map") return
    syncPanelModeInUrl("locations", mode, { history: "replace" })
  }, [dialogMode, hasExplicitModeParam, mode])

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
      metrics: ["visitors"] as ListMetricKey[],
      results: sliced,
      meta: { ...data.payload.meta, hasMore: data.payload.results.length > 9 },
    }
  }, [data])

  const handleCountrySelect = useCallback(
    (countryCode: string, countryLabel?: string) => {
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
      syncPanelModeInUrl("locations", "regions", { history: "replace" })
    },
    [closeDetailsDialog, site.domain, updateQuery]
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
      syncPanelModeInUrl("locations", "cities", { history: "replace" })
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
                localStorage.setItem(
                  `${STORAGE_PREFIX}.${site.domain}`,
                  tab.value
                )
                syncPanelModeInUrl("locations", tab.value)
              }}
            >
              {tab.label}
            </PanelTab>
          ))}
        </PanelTabs>
      </header>

      {loading ? (
        <div className="flex h-48 items-center justify-center text-sm text-muted-foreground">
          Loading…
        </div>
      ) : data.type === "map" ? (
        <>
          <CountriesMap
            data={data.payload}
            onSelectCountry={handleCountrySelect}
          />
          <div className="flex justify-center pt-0">
            <DetailsButton
              onClick={() => {
                try {
                  const sp = new URLSearchParams(window.location.search)
                  sp.delete("dialog")
                  setPanelModeSearchParam(sp, "locations", mode)
                  const seg = locationsSegmentForMode(
                    mode as "map" | "countries" | "regions" | "cities"
                  )
                  window.history.pushState(
                    {},
                    "",
                    buildDialogPath(seg, sp.toString())
                  )
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
            <div className="flex h-40 items-center justify-center text-sm text-muted-foreground">
              No data yet
            </div>
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
                  setPanelModeSearchParam(sp, "locations", mode)
                  const seg = locationsSegmentForMode(
                    mode as "map" | "countries" | "regions" | "cities"
                  )
                  window.history.pushState(
                    {},
                    "",
                    buildDialogPath(seg, sp.toString())
                  )
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
              setPanelModeSearchParam(sp, "locations", mode)
              const qs = sp.toString()
              if (open) {
                const seg = locationsSegmentForMode(
                  mode as "map" | "countries" | "regions" | "cities"
                )
                window.history.pushState({}, "", buildDialogPath(seg, qs))
              } else {
                window.history.pushState({}, "", baseAnalyticsPath(qs))
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

type CountriesMapProps = {
  data: MapPayload
  onSelectCountry: (isoCode: string, label?: string) => void
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
type GeoFeature = any

function CountriesMap({ data, onSelectCountry }: CountriesMapProps) {
  const [tooltip, setTooltip] = useState<{
    x: number
    y: number
    name: string
    flag?: string | null
    visitors: number
    width: number
    height: number
  } | null>(null)

  const features = useMemo(() => {
    try {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const topology = worldTopology as any
      const collection = feature(
        topology,
        topology.objects.countries
      ) as unknown as { features: GeoFeature[] }
      return collection.features.filter((featureItem) => {
        const id = String(featureItem.id)
        const name = String(
          featureItem.properties?.name ||
            featureItem.properties?.NAME ||
            featureItem.properties?.ADMIN ||
            ""
        )
        if (id === "010") return false // Antarctica ISO numeric code
        if (/antarctica/i.test(name)) return false
        return true
      })
    } catch (error) {
      console.error("Failed to prepare map features", error)
      return []
    }
  }, [])

  const lookup = useMemo(() => {
    const map = new Map<
      string,
      { visitors: number; code?: string; name: string }
    >()
    data.map.results.forEach((entry) => {
      const record = {
        visitors: entry.visitors,
        code: entry.code?.toUpperCase(),
        name: entry.name,
      }

      // Map by numeric code (used by TopoJSON)
      if (entry.numeric) {
        map.set(entry.numeric, record)
      }

      // Also map by alpha3 and alpha2 for compatibility
      const alpha3 = entry.alpha3?.toUpperCase()
      if (alpha3) {
        map.set(alpha3, record)
      }
      const alpha2 = entry.alpha2?.toUpperCase()
      if (alpha2) {
        map.set(alpha2, record)
      }
    })
    return map
  }, [data])

  // Build a projection that always fits the loaded features with a small margin
  const projection = useMemo(() => {
    const p = geoMercator()
    if (features.length > 0) {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const fc = { type: "FeatureCollection", features } as any
      return p.fitExtent(
        [
          [MAP_MARGIN_X, MAP_MARGIN_Y],
          [MAP_WIDTH - MAP_MARGIN_X, MAP_HEIGHT - MAP_MARGIN_Y],
        ],
        fc
      )
    }
    // Sensible fallback before features load (same aspect as viewBox)
    return p
      .scale((MAP_WIDTH - 2 * MAP_MARGIN_X) / (2 * Math.PI))
      .translate([MAP_WIDTH / 2, MAP_HEIGHT / 2])
  }, [features])
  const pathGenerator = useMemo(() => geoPath(projection), [projection])
  const max = Math.max(
    ...Array.from(lookup.values()).map((value) => value.visitors),
    1
  )

  return (
    <div className="relative overflow-hidden rounded-xs border border-border/70 bg-card">
      <svg
        role="img"
        aria-label="World map highlighting visitor distribution"
        viewBox={`0 0 ${MAP_WIDTH} ${MAP_HEIGHT}`}
        className="h-auto w-full"
        preserveAspectRatio="xMidYMid meet"
      >
        <g>
          {features.map((featureItem) => {
            // Try numeric ID first (TopoJSON uses ISO 3166-1 numeric codes)
            const numericId = String(featureItem.id)
            const alpha3Candidate = featureItem.properties?.ISO_A3
            const iso2Candidate = featureItem.properties?.ISO_A2

            const record =
              lookup.get(numericId) ||
              (typeof alpha3Candidate === "string" &&
                lookup.get(alpha3Candidate.toUpperCase())) ||
              (typeof iso2Candidate === "string" &&
                lookup.get(iso2Candidate.toUpperCase()))

            const intensity = record ? record.visitors / max : 0
            const fill = record ? colorForIntensity(intensity) : MAP_IDLE_FILL
            const stroke = record ? MAP_ACTIVE_STROKE : MAP_IDLE_STROKE
            const path = pathGenerator(featureItem)
            if (!path) return null

            return (
              <path
                key={
                  (typeof alpha3Candidate === "string"
                    ? alpha3Candidate
                    : iso2Candidate) ?? path
                }
                d={path}
                fill={fill}
                stroke={stroke}
                strokeWidth={record ? 0.95 : 0.65}
                className="cursor-pointer transition-all duration-150 hover:brightness-[1.06]"
                onClick={() => {
                  if (record) {
                    onSelectCountry(
                      record.code ?? String(alpha3Candidate ?? iso2Candidate),
                      record.name
                    )
                  }
                }}
                onMouseMove={(event) => {
                  if (!record) {
                    setTooltip(null)
                    return
                  }
                  const bounds =
                    event.currentTarget.ownerSVGElement?.getBoundingClientRect()
                  if (!bounds) return
                  const pretty = prettifyCountryName(record.name)
                  const flag =
                    flagFromIso2(record.code ?? String(iso2Candidate ?? "")) ||
                    null
                  setTooltip({
                    name: pretty,
                    flag,
                    visitors: record.visitors,
                    x: event.clientX - bounds.left,
                    y: event.clientY - bounds.top,
                    width: bounds.width,
                    height: bounds.height,
                  })
                }}
                onMouseLeave={() => setTooltip(null)}
              />
            )
          })}
        </g>
      </svg>
      <div className="flex items-center justify-between border-t border-border/60 px-3 py-2.5">
        <div className="text-[11px] tracking-[0.16em] text-muted-foreground uppercase">
          Visitor intensity
        </div>
        <div className="flex items-center gap-2 text-[11px] text-muted-foreground">
          <span>Sparse</span>
          <div
            aria-hidden="true"
            className="h-2 w-30 rounded-full ring-1 ring-border/60"
            style={{
              background: `linear-gradient(90deg, ${MAP_COLOR_STOPS.join(", ")})`,
            }}
          />
          <span>Dense</span>
        </div>
      </div>
      {tooltip ? (
        <div
          className="pointer-events-none absolute z-50 rounded-xl border border-border/70 bg-popover/96 p-3 text-popover-foreground shadow-xl backdrop-blur-sm"
          style={{
            left: Math.min(tooltip.x + 12, tooltip.width - 200),
            top: Math.min(tooltip.y + 12, tooltip.height - 72),
            minWidth: "160px",
          }}
        >
          <div className="mb-1 flex items-center gap-1.5">
            {tooltip.flag ? (
              <span aria-hidden className="shrink-0 text-sm leading-[18px]">
                {tooltip.flag}
              </span>
            ) : null}
            <p className="truncate text-sm font-medium text-foreground">
              {tooltip.name}
            </p>
          </div>
          <div className="flex items-baseline gap-1.5">
            <span className="text-lg font-medium text-foreground">
              {numberShortFormatter(tooltip.visitors)}
            </span>
            <span className="text-xs text-muted-foreground">Visitors</span>
          </div>
        </div>
      ) : null}
    </div>
  )
}

function colorForIntensity(value: number) {
  const clamped = Math.min(Math.max(value, 0), 1)
  const scaled = clamped * (MAP_COLOR_STOPS.length - 1)
  const index = Math.min(Math.floor(scaled), MAP_COLOR_STOPS.length - 2)
  const mix = scaled - index
  const from = MAP_COLOR_STOPS[index]
  const to = MAP_COLOR_STOPS[index + 1]
  const fromWeight = Math.round((1 - mix) * 100)
  const toWeight = 100 - fromWeight

  return `color-mix(in oklch, ${from} ${fromWeight}%, ${to} ${toWeight}%)`
}

// Emoji flag from ISO 3166-1 alpha-2
function flagFromIso2(code?: string) {
  if (!code) return ""
  const iso2 = code.toUpperCase()
  if (!/^[A-Z]{2}$/.test(iso2)) return ""
  const A = 0x1f1e6 // regional indicator 'A'
  const chars = Array.from(iso2).map((c) =>
    String.fromCodePoint(A + (c.charCodeAt(0) - 65))
  )
  return chars.join("")
}

// Prefer short, user-friendly country names for UI tooltips
function prettifyCountryName(name: string): string {
  const str = String(name || "")
  const direct: Record<string, string> = {
    "United States of America (the)": "United States",
    "United States of America": "United States",
    "Viet Nam": "Vietnam",
  }
  if (direct[str]) return direct[str]
  // Trim trailing " (the)"
  const cleaned = str.replace(/\s*\(the\)\s*$/i, "").trim()
  return cleaned
}
