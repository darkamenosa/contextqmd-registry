import { useCallback, useMemo, useState } from "react"

import { useAnalyticsApi } from "../hooks/use-analytics-api"
import { usePanelData } from "../hooks/use-panel-data"
import { useAnalyticsHost } from "../host-context"
import { limitListPayloadForCard, pickCardMetrics } from "../lib/card-metrics"
import {
  pagesModeForSegment,
  pagesSegmentForMode,
  parseDialogFromPath,
  type PagesMode,
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

type CardPagesMode = "pages" | "entry" | "exit"

const PAGE_TABS: Array<{
  value: CardPagesMode
  label: string
  short: string
}> = [
  { value: "pages", label: "Top Pages", short: "Top Pages" },
  { value: "entry", label: "Entry Pages", short: "Entry Pages" },
  { value: "exit", label: "Exit Pages", short: "Exit Pages" },
]

const TITLE_FOR_MODE: Record<string, string> = {
  pages: "Top Pages",
  seo: "SEO Pages",
  entry: "Entry Pages",
  exit: "Exit Pages",
}

const STORAGE_PREFIX = "admin.analytics.pages"

function normalizeCardMode(mode: string): CardPagesMode {
  switch (mode) {
    case "entry":
    case "exit":
      return mode
    default:
      return "pages"
  }
}

function firstColumnLabelForMode(mode: PagesMode) {
  switch (mode) {
    case "entry":
      return "Entry page"
    case "exit":
      return "Exit page"
    default:
      return "Page"
  }
}

function drillKeyForMode(mode: PagesMode) {
  switch (mode) {
    case "entry":
      return "entry_page"
    case "exit":
      return "exit_page"
    default:
      return "page"
  }
}

type PagesPanelProps = {
  initialData: ListPayload
  initialMode: string
}

export default function PagesPanel({
  initialData,
  initialMode,
}: PagesPanelProps) {
  const { fetchPages } = useAnalyticsApi()
  const host = useAnalyticsHost()
  const { query, updateQuery } = useQueryContext()
  const site = useSiteContext()

  const [preferredMode, setPreferredMode] = useState<CardPagesMode>(() =>
    normalizeCardMode(initialMode)
  )
  const { value: baseQuery } = useScopedQuery(query, {
    omitMode: true,
    omitMetric: true,
    omitInterval: true,
  })
  const storageKey = analyticsPreferenceKey(STORAGE_PREFIX, site.domain)
  const dialogMode = useMemo(() => {
    const parsed = parseDialogFromPath(host.pathname, host.reportsPath)
    if (parsed.type !== "segment") return null
    return pagesModeForSegment(parsed.segment)
  }, [host.pathname, host.reportsPath])
  const mode = preferredMode
  const detailsMode: PagesMode = dialogMode ?? preferredMode
  const detailsOpen = Boolean(dialogMode)
  const initialRequestKey = useMemo(
    () => JSON.stringify([baseQuery, normalizeCardMode(initialMode)]),
    [baseQuery, initialMode]
  )
  const requestKey = useMemo(
    () => JSON.stringify([baseQuery, mode]),
    [baseQuery, mode]
  )
  const closeDetailsDialog = host.closeDialogRoute
  const panelState = usePanelData({
    initialData,
    initialRequestKey,
    requestKey,
    fetchData: (controller) =>
      fetchPages(baseQuery, { mode }, controller.signal),
  })
  const data = panelState.data
  const loading = panelState.loading

  const highlightMetric = data.metrics.includes("visitors")
    ? "visitors"
    : data.metrics[0]
  const activeTitle = TITLE_FOR_MODE[mode] ?? "Pages"
  const detailsTitle = TITLE_FOR_MODE[detailsMode] ?? "Pages"
  const firstColumnLabel = firstColumnLabelForMode(mode)

  const drillInto = useCallback(
    (value: string, modeValue: PagesMode = mode) => {
      const drillKey = drillKeyForMode(modeValue)
      updateQuery((current) => ({
        ...current,
        filters: { ...current.filters, [drillKey]: value },
      }))
    },
    [mode, updateQuery]
  )

  // Limit card view to top 9 by the first metric; Details uses full list
  const limitedData = useMemo(
    (): ListPayload =>
      limitListPayloadForCard(data, {
        metrics: pickCardMetrics(data.metrics),
      }),
    [data]
  )

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
            revealSecondaryMetricsOnHover
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
                  const seg = pagesSegmentForMode(mode)
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
            const seg = pagesSegmentForMode(detailsMode)
            host.syncDialogRoute(open, (search) =>
              host.buildDialogPath(seg, search)
            )
          } catch {
            // Ignore history errors when syncing the modal route.
          }
        }}
        title={detailsTitle}
        endpoint={host.scopedPath("/pages")}
        extras={{ mode: detailsMode }}
        defaultSortKey={detailsMode === "seo" ? "clicks" : "visitors"}
        firstColumnLabel={firstColumnLabelForMode(detailsMode)}
        onRowClick={(item) => {
          drillInto(String(item.name), detailsMode)
          closeDetailsDialog()
        }}
      />
    </section>
  )
}
