import { useCallback, useMemo, useState } from "react"

import { fetchPages } from "../api"
import { usePanelData } from "../hooks/use-panel-data"
import {
  openReportsDialogRoute,
  syncReportsDialogRoute,
  useCloseReportsDialogRoute,
} from "../hooks/use-reports-dialog-route"
import { pickCardMetrics } from "../lib/card-metrics"
import {
  buildDialogPath,
  pagesModeForSegment,
  pagesSegmentForMode,
  parseDialogFromPath,
} from "../lib/dialog-path"
import {
  analyticsPreferenceKey,
  writeAnalyticsPreference,
} from "../lib/preferences"
import { useScopedQuery } from "../lib/query-scope"
import { useQueryContext } from "../query-context"
import { useSiteContext } from "../site-context"
import type { ListPayload } from "../types"
import DetailsButton from "./details-button"
import { MetricTable, PanelEmptyState, PanelListSkeleton } from "./list-table"
import { PanelTab, PanelTabs } from "./panel-tabs"
import RemoteDetailsDialog from "./remote-details-dialog"

const PAGE_TABS: Array<{ value: string; label: string; short: string }> = [
  { value: "pages", label: "Top Pages", short: "Top Pages" },
  { value: "entry", label: "Entry Pages", short: "Entry Pages" },
  { value: "exit", label: "Exit Pages", short: "Exit Pages" },
]

const TITLE_FOR_MODE: Record<string, string> = {
  pages: "Top Pages",
  entry: "Entry Pages",
  exit: "Exit Pages",
}

const STORAGE_PREFIX = "admin.analytics.pages"

type PagesPanelProps = {
  initialData: ListPayload
  initialMode: string
}

export default function PagesPanel({
  initialData,
  initialMode,
}: PagesPanelProps) {
  const { query, pathname, updateQuery } = useQueryContext()
  const site = useSiteContext()

  const [preferredMode, setPreferredMode] = useState(() => initialMode)
  const { value: baseQuery } = useScopedQuery(query, {
    omitMode: true,
    omitMetric: true,
    omitInterval: true,
  })
  const storageKey = analyticsPreferenceKey(STORAGE_PREFIX, site.domain)
  const dialogMode = useMemo(() => {
    const parsed = parseDialogFromPath(pathname)
    if (parsed.type !== "segment") return null
    return pagesModeForSegment(parsed.segment)
  }, [pathname])
  const mode = dialogMode ?? preferredMode
  const detailsOpen = Boolean(dialogMode)
  const initialRequestKey = useMemo(
    () => JSON.stringify([baseQuery, initialMode]),
    [baseQuery, initialMode]
  )
  const requestKey = useMemo(
    () => JSON.stringify([baseQuery, mode]),
    [baseQuery, mode]
  )
  const closeDetailsDialog = useCloseReportsDialogRoute()
  const panelState = usePanelData({
    initialData,
    initialRequestKey,
    requestKey,
    fetchData: (controller) =>
      fetchPages(baseQuery, { mode }, controller.signal),
  })
  const data = panelState.data
  const loading = panelState.loading

  const highlightMetric = useMemo(
    () => (data.metrics.includes("visitors") ? "visitors" : data.metrics[0]),
    [data.metrics]
  )

  const activeTitle = useMemo(() => TITLE_FOR_MODE[mode] ?? "Pages", [mode])

  const firstColumnLabel = useMemo(() => {
    switch (mode) {
      case "entry":
        return "Entry page"
      case "exit":
        return "Exit page"
      default:
        return "Page"
    }
  }, [mode])

  const drillKey = useMemo(() => {
    switch (mode) {
      case "entry":
        return "entry_page"
      case "exit":
        return "exit_page"
      default:
        return "page"
    }
  }, [mode])

  const drillInto = useCallback(
    (value: string) => {
      updateQuery((current) => ({
        ...current,
        filters: { ...current.filters, [drillKey]: value },
      }))
    },
    [drillKey, updateQuery]
  )

  // Limit card view to top 9 by the first metric; Details uses full list
  const limitedData = useMemo((): ListPayload => {
    const metricKey = data.metrics[0] ?? "visitors"
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
      data-testid="pages-panel"
    >
      <header className="flex flex-wrap items-center justify-between gap-3">
        <h2 className="text-base font-medium">{activeTitle}</h2>
        <PanelTabs>
          {PAGE_TABS.map((tab) => (
            <PanelTab
              key={tab.value}
              active={mode === tab.value}
              onClick={() => {
                setPreferredMode(tab.value)
                writeAnalyticsPreference(storageKey, tab.value)
              }}
            >
              {tab.short}
            </PanelTab>
          ))}
        </PanelTabs>
      </header>

      {loading ? (
        <PanelListSkeleton
          firstColumnLabel={firstColumnLabel}
          metricLabel={
            mode === "entry"
              ? "Unique Entrances"
              : mode === "exit"
                ? "Unique Exits"
                : "Visitors"
          }
        />
      ) : data.results.length === 0 ? (
        <PanelEmptyState />
      ) : (
        <>
          <MetricTable
            data={limitedData}
            highlightedMetric={highlightMetric ?? "visitors"}
            onRowClick={(item) => drillInto(String(item.name))}
            displayBars={false}
            firstColumnLabel={firstColumnLabel}
            metricLabels={
              mode === "entry"
                ? { visitors: "Unique Entrances" }
                : mode === "exit"
                  ? { visitors: "Unique Exits" }
                  : undefined
            }
            barColorTheme="cyan"
            testId="pages"
          />
          <div className="mt-auto flex justify-center pt-3">
            <DetailsButton
              data-testid="pages-details-btn"
              onClick={() => {
                try {
                  const seg = pagesSegmentForMode(
                    mode as "pages" | "entry" | "exit"
                  )
                  openReportsDialogRoute((search) =>
                    buildDialogPath(seg, search)
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
            const seg = pagesSegmentForMode(mode as "pages" | "entry" | "exit")
            syncReportsDialogRoute(open, (search) =>
              buildDialogPath(seg, search)
            )
          } catch {
            // Ignore history errors when syncing the modal route.
          }
        }}
        title={activeTitle}
        endpoint={"/admin/analytics/pages"}
        extras={{ mode }}
        defaultSortKey={"visitors"}
        firstColumnLabel={firstColumnLabel}
        onRowClick={(item) => {
          drillInto(String(item.name))
          closeDetailsDialog()
        }}
      />
    </section>
  )
}
