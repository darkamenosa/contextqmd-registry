import {
  startTransition,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react"

import { fetchDevices } from "../api"
import {
  categorizeScreenSize,
  getBrowserIcon,
  getOSIcon,
} from "../lib/device-visuals"
import {
  baseAnalyticsPath,
  buildDialogPath,
  devicesModeForSegment,
  devicesSegmentForMode,
  parseDialogFromPath,
} from "../lib/dialog-path"
import {
  DEVICES_MODES,
  getDevicesModeFromSearch,
  inferDevicesModeFromFilters,
  readStoredMode,
} from "../lib/panel-mode"
import { useScopedQuery } from "../lib/query-scope"
import { useQueryContext } from "../query-context"
import { useSiteContext } from "../site-context"
import type { DevicesPayload, ListMetricKey } from "../types"
import DetailsButton from "./details-button"
import { MetricTable, PanelEmptyState, PanelListSkeleton } from "./list-table"
import { PanelTab, PanelTabs } from "./panel-tabs"
import RemoteDetailsDialog from "./remote-details-dialog"

const DEVICE_TABS: Array<{ value: "browser" | "os" | "size"; label: string }> =
  [
    { value: "browser", label: "Browser" },
    { value: "os", label: "OS" },
    { value: "size", label: "Size" },
  ]

const TAB_TO_MODE: Record<"browser" | "os" | "size", string> = {
  browser: "browsers",
  os: "operating-systems",
  size: "screen-sizes",
}

const MODE_TO_TAB: Record<string, "browser" | "os" | "size"> = {
  browsers: "browser",
  "browser-versions": "browser",
  "operating-systems": "os",
  "operating-system-versions": "os",
  "screen-sizes": "size",
}

const STORAGE_PREFIX = "admin.analytics.devices"

type DevicesPanelProps = {
  initialData: DevicesPayload
}

export default function DevicesPanel({ initialData }: DevicesPanelProps) {
  const { query, pathname, search, updateQuery } = useQueryContext()
  const site = useSiteContext()
  const initialBaseMode =
    getDevicesModeFromSearch(search, query.mode) ??
    readStoredMode(`${STORAGE_PREFIX}.${site.domain}`, DEVICES_MODES) ??
    "browsers"
  const initialMode = inferDevicesModeFromFilters(
    initialBaseMode,
    query.filters
  )

  const [preferredMode, setPreferredMode] = useState(() => initialBaseMode)
  const [data, setData] = useState<DevicesPayload>(initialData)
  const [loading, setLoading] = useState(false)
  const { value: baseQuery } = useScopedQuery(query, {
    omitMode: true,
    omitMetric: true,
    omitInterval: true,
  })
  const dialogMode = useMemo(() => {
    const parsed = parseDialogFromPath(pathname)
    if (parsed.type !== "segment") return null
    return devicesModeForSegment(parsed.segment)
  }, [pathname])
  const baseMode = dialogMode ?? preferredMode
  const mode = useMemo(
    () => inferDevicesModeFromFilters(baseMode, query.filters),
    [baseMode, query.filters]
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

  const closeDetailsDialog = useCallback(() => {
    try {
      const sp = new URLSearchParams(window.location.search)
      sp.delete("dialog")
      window.history.pushState({}, "", baseAnalyticsPath(sp.toString()))
    } catch {
      // Ignore history errors; local dialog state remains authoritative.
    }
  }, [])

  useEffect(() => {
    if (requestKey === lastRequestKeyRef.current) return
    lastRequestKeyRef.current = requestKey

    const controller = new AbortController()
    startTransition(() => setLoading(true))
    fetchDevices(baseQuery, { mode }, controller.signal)
      .then(setData)
      .catch((error) => {
        if (error.name !== "AbortError") console.error(error)
      })
      .finally(() => setLoading(false))

    return () => controller.abort()
  }, [baseQuery, mode, requestKey])

  const highlightMetric = useMemo<ListMetricKey>(() => "visitors", [])

  const activeTitle = useMemo(() => {
    switch (mode) {
      case "browser-versions":
        return "Browser Versions"
      case "operating-systems":
        return "Operating Systems"
      case "operating-system-versions":
        return "OS Versions"
      case "screen-sizes":
        return "Screen Sizes"
      case "browsers":
      default:
        return "Browsers"
    }
  }, [mode])

  const activeTab = useMemo(() => MODE_TO_TAB[mode] ?? "browser", [mode])
  const dialogBaseMode = useMemo(() => TAB_TO_MODE[activeTab], [activeTab])

  const firstColumnLabel = useMemo(() => {
    switch (activeTab) {
      case "browser":
        return "Browser"
      case "os":
        return "OS"
      case "size":
        return "Screen Size"
      default:
        return "Item"
    }
  }, [activeTab])

  const setAndStoreMode = useCallback(
    (next: string) => {
      setPreferredMode(next)
      if (typeof window !== "undefined") {
        localStorage.setItem(`${STORAGE_PREFIX}.${site.domain}`, next)
      }
    },
    [site.domain]
  )

  const handleSelect = useCallback(
    (itemName: string) => {
      updateQuery((current) => {
        const filters = { ...current.filters }
        const next = { ...current, filters }
        if (mode === "browser-versions") {
          filters.browser_version = itemName
        } else if (mode === "operating-system-versions") {
          filters.os_version = itemName
        } else if (mode === "operating-systems") {
          filters.os = itemName
        } else if (mode === "screen-sizes") {
          filters.size = itemName
        } else {
          filters.browser = itemName
        }
        return next
      })
    },
    [mode, updateQuery]
  )

  // Limit card view to top 9 by the first metric; Details keeps full list
  const limitedData = useMemo((): DevicesPayload => {
    const metricKey = "visitors"
    const sorted = [...data.results].sort((a, b) => {
      const av = Number(a[metricKey] ?? 0)
      const bv = Number(b[metricKey] ?? 0)
      if (av === bv) return String(a.name).localeCompare(String(b.name))
      return bv - av
    })
    const sliced = sorted.slice(0, 9)
    return {
      ...data,
      metrics: pickCardMetrics(data.metrics),
      results: sliced,
      meta: { ...data.meta, hasMore: data.results.length > 9 },
    }
  }, [data])

  return (
    <section
      className="flex flex-col gap-3 rounded-lg border border-border bg-card p-4"
      data-testid="devices-panel"
    >
      <header className="flex flex-wrap items-center justify-between gap-3">
        <h2 className="text-base font-medium">Devices</h2>
        <PanelTabs>
          {DEVICE_TABS.map((tab) => (
            <PanelTab
              key={tab.value}
              active={activeTab === tab.value}
              onClick={() => setAndStoreMode(TAB_TO_MODE[tab.value])}
            >
              {tab.label}
            </PanelTab>
          ))}
        </PanelTabs>
      </header>

      {loading ? (
        <PanelListSkeleton
          firstColumnLabel={firstColumnLabel}
          metricLabel="%"
        />
      ) : data.results.length === 0 ? (
        <PanelEmptyState />
      ) : (
        <>
          <MetricTable
            data={limitedData}
            highlightedMetric={highlightMetric ?? "percentage"}
            onRowClick={(item) => handleSelect(String(item.name))}
            renderLeading={(item) => renderDeviceLeading(mode, item)}
            displayBars={false}
            firstColumnLabel={firstColumnLabel}
            barColorTheme="cyan"
            testId="devices"
          />
          <div className="mt-auto flex justify-center pt-3">
            <DetailsButton
              data-testid="devices-details-btn"
              onClick={() => {
                try {
                  const sp = new URLSearchParams(window.location.search)
                  sp.delete("dialog")
                  const seg = devicesSegmentForMode(
                    dialogBaseMode as
                      | "browsers"
                      | "operating-systems"
                      | "screen-sizes"
                  )
                  window.history.pushState(
                    {},
                    "",
                    buildDialogPath(seg, sp.toString())
                  )
                } catch {
                  // Ignore history errors when opening the details modal.
                }
              }}
            >
              Details
            </DetailsButton>
          </div>
        </>
      )}

      <RemoteDetailsDialog
        open={detailsOpen}
        onOpenChange={(open) => {
          try {
            const sp = new URLSearchParams(window.location.search)
            sp.delete("dialog")
            const qs = sp.toString()
            if (open) {
              const seg = devicesSegmentForMode(
                dialogBaseMode as
                  | "browsers"
                  | "operating-systems"
                  | "screen-sizes"
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
        endpoint={"/admin/analytics/devices"}
        extras={{ mode }}
        firstColumnLabel={firstColumnLabel}
        defaultSortKey={"visitors"}
        onRowClick={(item) => {
          handleSelect(String(item.name))
          closeDetailsDialog()
        }}
        renderLeading={(item) => renderDeviceLeading(mode, item)}
      />
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

function renderDeviceLeading(mode: string, item: Record<string, unknown>) {
  const tab = MODE_TO_TAB[mode] ?? "browser"

  if (tab === "browser") {
    const name = String(
      (item as Record<string, unknown>).browser ?? item.name ?? ""
    )
    return <BrowserIcon name={name} />
  }

  if (tab === "os") {
    const name = String((item as Record<string, unknown>).os ?? item.name ?? "")
    return <OSIcon name={name} />
  }

  // Screen sizes - use SVG icons like Plausible
  const name = String(item.name ?? "")
  return <ScreenSizeIcon screenSize={name} />
}

// Match Plausible's exact icon rendering approach
function BrowserIcon({ name }: { name: string }) {
  const filename = getBrowserIcon(name)
  return (
    <img
      alt=""
      src={`/images/icon/browser/${filename}`}
      className="mr-2 size-5 shrink-0 object-contain"
    />
  )
}

function OSIcon({ name }: { name: string }) {
  const filename = getOSIcon(name)
  return (
    <img
      alt=""
      src={`/images/icon/os/${filename}`}
      className="mr-2 size-5 shrink-0 object-contain"
    />
  )
}

// Screen size icons - SVG from Feather Icons (same as Plausible)
function ScreenSizeIcon({ screenSize }: { screenSize: string }) {
  // Categorize by screen size dimensions
  const category = categorizeScreenSize(screenSize)

  if (category === "Mobile") {
    return (
      <span className="mr-2">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          width="24"
          height="24"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
          className="size-4"
        >
          <rect x="5" y="2" width="14" height="20" rx="2" ry="2" />
          <line x1="12" y1="18" x2="12" y2="18" />
        </svg>
      </span>
    )
  }

  if (category === "Tablet") {
    return (
      <span className="mr-2">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          width="24"
          height="24"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
          className="size-4"
        >
          <rect
            x="4"
            y="2"
            width="16"
            height="20"
            rx="2"
            ry="2"
            transform="rotate(180 12 12)"
          />
          <line x1="12" y1="18" x2="12" y2="18" />
        </svg>
      </span>
    )
  }

  if (category === "Laptop") {
    return (
      <span className="mr-2">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          width="24"
          height="24"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
          className="size-4"
        >
          <rect x="2" y="3" width="20" height="14" rx="2" ry="2" />
          <line x1="2" y1="20" x2="22" y2="20" />
        </svg>
      </span>
    )
  }

  if (category === "Desktop") {
    return (
      <span className="mr-2">
        <svg
          xmlns="http://www.w3.org/2000/svg"
          width="24"
          height="24"
          viewBox="0 0 24 24"
          fill="none"
          stroke="currentColor"
          strokeWidth="2"
          strokeLinecap="round"
          strokeLinejoin="round"
          className="size-4"
        >
          <rect x="2" y="3" width="20" height="14" rx="2" ry="2" />
          <line x1="8" y1="21" x2="16" y2="21" />
          <line x1="12" y1="17" x2="12" y2="21" />
        </svg>
      </span>
    )
  }

  return null
}
