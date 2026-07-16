import { useCallback, useMemo, useState } from "react"

import { useAnalyticsApi } from "../hooks/use-analytics-api"
import { usePanelData } from "../hooks/use-panel-data"
import { useAnalyticsHost } from "../host-context"
import { limitListPayloadForCard, pickCardMetrics } from "../lib/card-metrics"
import {
  categorizeScreenSize,
  getBrowserIcon,
  getOSIcon,
} from "../lib/device-visuals"
import {
  devicesModeForSegment,
  devicesSegmentForMode,
  parseDialogFromPath,
} from "../lib/dialog-path"
import { inferDevicesModeFromFilters } from "../lib/panel-mode"
import {
  analyticsPreferenceKey,
  writeAnalyticsPreference,
} from "../lib/preferences"
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
  initialBaseMode: string
  initialMode: string
}

export default function DevicesPanel({
  initialData,
  initialBaseMode,
  initialMode,
}: DevicesPanelProps) {
  const { fetchDevices } = useAnalyticsApi()
  const host = useAnalyticsHost()
  const { query, updateQuery } = useQueryContext()
  const site = useSiteContext()

  const [preferredMode, setPreferredMode] = useState(() => initialBaseMode)
  const { value: baseQuery } = useScopedQuery(query, {
    omitMode: true,
    omitMetric: true,
    omitInterval: true,
  })
  const storageKey = analyticsPreferenceKey(STORAGE_PREFIX, site.domain)
  const dialogMode = useMemo(() => {
    const parsed = parseDialogFromPath(host.pathname, host.reportsPath)
    if (parsed.type !== "segment") return null
    return devicesModeForSegment(parsed.segment)
  }, [host.pathname, host.reportsPath])
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
  const panelState = usePanelData({
    initialData,
    initialRequestKey,
    requestKey,
    fetchData: (controller) =>
      fetchDevices(baseQuery, { mode }, controller.signal),
  })
  const data = panelState.data
  const loading = panelState.loading

  const highlightMetric: ListMetricKey = "visitors"
  const activeTitle =
    mode === "browser-versions"
      ? "Browser Versions"
      : mode === "operating-systems"
        ? "Operating Systems"
        : mode === "operating-system-versions"
          ? "OS Versions"
          : mode === "screen-sizes"
            ? "Screen Sizes"
            : "Browsers"
  const activeTab = MODE_TO_TAB[mode] ?? "browser"
  const dialogBaseMode = TAB_TO_MODE[activeTab]
  const firstColumnLabel =
    activeTab === "browser"
      ? "Browser"
      : activeTab === "os"
        ? "OS"
        : activeTab === "size"
          ? "Screen Size"
          : "Item"

  const setAndStoreMode = useCallback(
    (next: string) => {
      setPreferredMode(next)
      writeAnalyticsPreference(storageKey, next)
    },
    [storageKey]
  )

  const handleSelect = useCallback(
    (itemName: string, closeDialog = false) => {
      updateQuery(
        (current) => {
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
        },
        { closeDialog }
      )
    },
    [mode, updateQuery]
  )

  // Limit card view to top 9 by the first metric; Details keeps full list
  const limitedData = useMemo(
    (): DevicesPayload =>
      limitListPayloadForCard(data, {
        metricKey: "visitors",
        metrics: pickCardMetrics(data.metrics),
      }),
    [data]
  )

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
            revealSecondaryMetricsOnHover
            testId="devices"
          />
          <div className="mt-auto flex justify-center pt-3">
            <DetailsButton
              data-testid="devices-details-btn"
              onClick={() => {
                try {
                  const seg = devicesSegmentForMode(
                    dialogBaseMode as
                      | "browsers"
                      | "operating-systems"
                      | "screen-sizes"
                  )
                  host.openDialogRoute((search) =>
                    host.buildDialogPath(seg, search)
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
            const seg = devicesSegmentForMode(
              dialogBaseMode as
                | "browsers"
                | "operating-systems"
                | "screen-sizes"
            )
            host.syncDialogRoute(open, (search) =>
              host.buildDialogPath(seg, search)
            )
          } catch {
            // Ignore history errors when syncing modal state.
          }
        }}
        title={`Top ${activeTitle}`}
        endpoint={host.scopedPath("/devices")}
        extras={{ mode }}
        firstColumnLabel={firstColumnLabel}
        defaultSortKey={"visitors"}
        onRowClick={(item) => handleSelect(String(item.name), true)}
        renderLeading={(item) => renderDeviceLeading(mode, item)}
      />
    </section>
  )
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
