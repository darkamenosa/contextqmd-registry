import type { ReactNode } from "react"
import { ExternalLink } from "lucide-react"

import { Skeleton } from "@/components/ui/skeleton"
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@/components/ui/tooltip"

import { flagFromIso2 } from "../lib/country-flag"
import { normalizeMetricKey } from "../lib/metric-key"
import {
  durationFormatter,
  fractionPercentageFormatter,
  nullable,
  numberShortFormatter,
  percentageFormatter,
} from "../lib/number-formatter"
import {
  formatTopStatChangeValue,
  topStatChangeDirection,
  topStatChangeTone,
} from "../lib/top-stat-change"
import type { ListItem, ListMetricKey, ListPayload } from "../types"

// eslint-disable-next-line react-refresh/only-export-components
export const METRIC_LABELS: Record<ListMetricKey, string> = {
  visitors: "Visitors",
  clicks: "Clicks",
  events: "Events",
  visits: "Visits",
  percentage: "%",
  uniques: "Uniques",
  total: "Total",
  conversionRate: "CR",
  exitRate: "Exit Rate",
  bounceRate: "Bounce Rate",
  visitDuration: "Visit duration",
  scrollDepth: "Scroll Depth",
  timeOnPage: "Time on Page",
  pageviews: "Pageviews",
  impressions: "Impressions",
  ctr: "CTR",
  position: "Position",
}

// eslint-disable-next-line react-refresh/only-export-components
export const FORMATTERS: Partial<
  Record<ListMetricKey, (value: number | null | undefined) => string>
> = {
  visitors: (value) => numberShortFormatter(value ?? 0),
  clicks: (value) => numberShortFormatter(value ?? 0),
  events: (value) => numberShortFormatter(value ?? 0),
  uniques: (value) => numberShortFormatter(value ?? 0),
  total: (value) => numberShortFormatter(value ?? 0),
  percentage: (value) => fractionPercentageFormatter(value ?? null),
  conversionRate: (value) => percentageFormatter(value ?? null),
  exitRate: (value) => percentageFormatter(value ?? null),
  bounceRate: (value) => percentageFormatter(value ?? null),
  visitDuration: nullable(durationFormatter),
  scrollDepth: (value) => percentageFormatter(value ?? null),
  timeOnPage: nullable(durationFormatter),
  pageviews: (value) => numberShortFormatter(value ?? 0),
  impressions: (value) => numberShortFormatter(value ?? 0),
  ctr: (value) => percentageFormatter(value ?? null),
  position: (value) => {
    if (value == null || Number.isNaN(value as number)) return "-"
    return (Math.round((value as number) * 10) / 10).toFixed(1)
  },
}

type MetricTableProps = {
  data: ListPayload
  highlightedMetric?: ListMetricKey
  onRowClick?: (item: ListItem) => void
  renderLeading?: (item: ListItem) => ReactNode
  rowBarClassName?: string
  displayBars?: boolean
  firstColumnLabel?: string
  barColorTheme?: "indigo" | "emerald" | "amber" | "violet" | "cyan"
  metricLabels?: Partial<Record<ListMetricKey, string>>
  revealSecondaryMetricsOnHover?: boolean
  // Optional test id root for system tests
  testId?: string
}

export function MetricTable({
  data,
  onRowClick,
  renderLeading,
  rowBarClassName,
  displayBars = true,
  firstColumnLabel,
  barColorTheme = "emerald",
  metricLabels,
  testId,
}: MetricTableProps) {
  const metrics = data.metrics
  const resolvedMetricLabels = metricLabels ?? data.meta.metricLabels
  // Base width used when labels are short
  const BASE_NUM_COL_MIN_PX = 72

  // Determine which metric to use for bar width to match Plausible:
  // Prefer 'visitors' when available; otherwise fall back to the first metric provided.
  const barMetric = metrics.includes("visitors") ? "visitors" : metrics[0]

  // Calculate max value for proportional bars
  const maxValue = Math.max(
    ...data.results.map((item) => Number(item[barMetric] ?? 0)),
    1
  )

  const itemLabel =
    firstColumnLabel ?? (data.meta.skipImportedReason ? "Item*" : "Item")

  // Color mapping based on theme
  const colorMap = {
    indigo: ["bg-primary/15", "bg-primary/12", "bg-primary/8"],
    emerald: ["bg-primary/12", "bg-primary/10", "bg-primary/6"],
    amber: ["bg-primary/10", "bg-primary/8", "bg-primary/5"],
    violet: ["bg-primary/8", "bg-primary/6", "bg-primary/4"],
    cyan: ["bg-primary/6", "bg-primary/5", "bg-primary/3"],
  }

  const metricWidth = (metric: string) => {
    const title =
      (resolvedMetricLabels && resolvedMetricLabels[metric as ListMetricKey]) ??
      METRIC_LABELS[normalizeMetricKey(metric)] ??
      metric
    const len = String(title).length
    return len >= 16 ? 144 : len >= 12 ? 120 : BASE_NUM_COL_MIN_PX
  }
  // Use new DevicesPanel styling when displayBars is false
  if (!displayBars) {
    return (
      <div
        className={`group/report overflow-hidden ${PANEL_MIN_HEIGHT_CLASS}`}
        data-testid={testId ? `${testId}-wrap` : undefined}
      >
        <table
          className="w-full table-fixed text-sm"
          data-testid={testId ? `${testId}-table` : undefined}
        >
          <colgroup>
            <col />
            {metrics.map((metric) => (
              <col key={metric} style={{ width: metricWidth(metric) }} />
            ))}
          </colgroup>
          <thead>
            <tr className="border-b border-border">
              <th
                scope="col"
                className="pr-3 pb-2 text-left text-xs font-semibold tracking-wide text-muted-foreground uppercase"
              >
                {itemLabel}
              </th>
              {metrics.map((metric) => (
                <th key={metric} scope="col" className="pb-2 pl-4 text-right">
                  <span className="inline-block text-right text-xs font-semibold tracking-wide whitespace-nowrap text-muted-foreground uppercase">
                    {(resolvedMetricLabels &&
                      resolvedMetricLabels[metric as ListMetricKey]) ??
                      METRIC_LABELS[normalizeMetricKey(metric)] ??
                      metric}
                  </span>
                </th>
              ))}
            </tr>
          </thead>
          <tbody className="divide-y divide-border">
            {data.results.map((item, index) => {
              // Calculate bar width based on bar metric value
              const value = Number(item[barMetric] ?? 0)
              const barWidth = Math.max((value / maxValue) * 100, 0)

              // Determine bar color based on theme
              const colors = colorMap[barColorTheme]
              const barColor =
                index === 0 ? colors[0] : index === 1 ? colors[1] : colors[2]

              // Determine if this row has a leading icon/flag
              const leadingEl = renderLeading
                ? renderLeading(item)
                : renderFlag(item)
              const hasLeading = Boolean(leadingEl)

              return (
                <tr
                  key={item.name}
                  className={`group relative h-9 transition ${onRowClick ? "cursor-pointer hover:bg-muted/20" : ""}`}
                  onClick={() => onRowClick?.(item)}
                  data-testid={testId ? `${testId}-row` : undefined}
                  data-name={String(item.name)}
                >
                  <td className="overflow-hidden pr-3">
                    <div
                      className={`relative flex min-w-0 items-center gap-3 ${hasLeading ? "pl-8" : "pl-2"}`}
                    >
                      <div
                        className={`absolute inset-y-[1px] left-0 rounded-xs ${barColor}`}
                        style={{ width: `${barWidth}%` }}
                        aria-hidden="true"
                      />
                      {hasLeading ? (
                        <span className="absolute left-1 z-10 inline-flex size-6 items-center justify-center">
                          {leadingEl}
                        </span>
                      ) : null}
                      <span className="relative z-10 flex min-w-0 flex-1 items-center gap-1 font-medium text-foreground">
                        <span className="truncate" title={String(item.name)}>
                          {item.name}
                        </span>
                        {isPathLike(item.name) ? (
                          <a
                            href={String(item.name)}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="shrink-0 text-muted-foreground hover:text-foreground"
                            onClick={(e) => e.stopPropagation()}
                            aria-label="Open page in new tab"
                            title={String(item.name)}
                          >
                            <ExternalLink className="size-3.5" />
                          </a>
                        ) : null}
                      </span>
                    </div>
                  </td>
                  {metrics.map((metric, metricIndex) => (
                    <td key={metric} className="pl-4 text-right">
                      <span
                        className={[
                          "whitespace-nowrap tabular-nums",
                          metricIndex === 0
                            ? "font-semibold text-foreground"
                            : "font-semibold text-muted-foreground",
                        ].join(" ")}
                      >
                        <MetricValueCell
                          item={item}
                          metric={metric}
                          meta={data.meta}
                        />
                      </span>
                    </td>
                  ))}
                </tr>
              )
            })}
          </tbody>
        </table>
        {data.meta.skipImportedReason && (
          <p className="px-4 py-2 text-xs text-muted-foreground">
            * Imported data omitted: {data.meta.skipImportedReason}
          </p>
        )}
      </div>
    )
  }

  // Original table with bars for other panels
  return (
    <div
      className={`overflow-hidden rounded-xs border ${PANEL_MIN_HEIGHT_CLASS}`}
    >
      <table
        className="min-w-full divide-y divide-border text-sm"
        data-testid={testId ? `${testId}-table` : undefined}
      >
        <thead className="bg-muted/40">
          <tr>
            <th
              scope="col"
              className="px-4 py-1.5 text-left font-semibold text-muted-foreground"
            >
              {itemLabel}
            </th>
            {metrics.map((metric) => (
              <th
                key={metric}
                scope="col"
                className="px-4 py-1.5 text-right font-semibold text-muted-foreground"
              >
                {METRIC_LABELS[normalizeMetricKey(metric)] ?? metric}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-border bg-background">
          {data.results.map((item) => (
            <tr
              key={item.name}
              className={`group transition hover:bg-muted/40 ${onRowClick ? "cursor-pointer" : ""}`}
              onClick={() => onRowClick?.(item)}
              data-testid={testId ? `${testId}-row` : undefined}
              data-name={String(item.name)}
            >
              <td className="px-4 py-1.5">
                <div className="relative flex items-center gap-2">
                  {rowBarClassName ? (
                    <span
                      aria-hidden
                      className={`pointer-events-none absolute inset-y-1 left-0 block rounded-xs ${rowBarClassName}`}
                      style={{
                        width: `${Math.max((Number(item[metrics[0]] ?? 0) / maxValue) * 100, 6)}%`,
                      }}
                    />
                  ) : null}
                  <span className="relative z-10 flex items-center gap-2">
                    {renderLeading ? renderLeading(item) : renderFlag(item)}
                    <span className="flex min-w-0 flex-1 items-center gap-1 font-medium text-foreground">
                      <span className="truncate" title={String(item.name)}>
                        {item.name}
                      </span>
                      {isPathLike(item.name) ? (
                        <a
                          href={String(item.name)}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="shrink-0 text-muted-foreground hover:text-foreground"
                          onClick={(e) => e.stopPropagation()}
                          aria-label="Open page in new tab"
                          title={String(item.name)}
                        >
                          <ExternalLink className="size-3.5" />
                        </a>
                      ) : null}
                    </span>
                  </span>
                </div>
              </td>
              {metrics.map((metric, idx) => (
                <td key={metric} className="px-4 py-1.5 text-right">
                  <div className="flex items-center justify-end gap-2.5">
                    {idx === 0 ? (
                      <span
                        aria-hidden
                        className="flex-1 rounded-full bg-primary/10"
                        style={{
                          maxWidth: 120,
                          height: 5,
                          position: "relative",
                        }}
                      >
                        <span
                          className="absolute inset-y-0 left-0 rounded-full bg-primary"
                          style={{
                            width: `${(Number(item[metric] ?? 0) / maxValue) * 100}%`,
                          }}
                        />
                      </span>
                    ) : null}
                    <span className="text-foreground tabular-nums">
                      <MetricValueCell
                        item={item}
                        metric={metric}
                        meta={data.meta}
                      />
                    </span>
                  </div>
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
      {data.meta.skipImportedReason && (
        <p className="px-4 py-2 text-xs text-muted-foreground">
          * Imported data omitted: {data.meta.skipImportedReason}
        </p>
      )}
    </div>
  )
}

/** Height of one table row (h-9 = 2.25rem) × 9 rows + header ≈ 22.5rem */
const PANEL_ROWS = 9
const PANEL_MIN_HEIGHT_CLASS = "min-h-[22.5rem]"
const SKELETON_BAR_WIDTHS = [82, 58, 50, 42, 68, 36, 62, 46, 32]

export function PanelListSkeleton({
  rows = PANEL_ROWS,
  firstColumnLabel = "Item",
  metricLabel = "Visitors",
}: {
  rows?: number
  firstColumnLabel?: string
  metricLabel?: string
}) {
  return (
    <div className="animate-pulse">
      <div className="flex items-center justify-between border-b border-border pb-2">
        <span className="text-xs font-semibold tracking-wide text-muted-foreground uppercase">
          {firstColumnLabel}
        </span>
        <span className="text-xs font-semibold tracking-wide text-muted-foreground uppercase">
          {metricLabel}
        </span>
      </div>
      <div className="divide-y divide-border/50">
        {Array.from({ length: rows }).map((_, i) => (
          <div key={i} className="flex h-9 items-center justify-between gap-4">
            <Skeleton
              className="h-5 rounded-sm"
              style={{
                width: `${SKELETON_BAR_WIDTHS[i % SKELETON_BAR_WIDTHS.length]}%`,
              }}
            />
            <Skeleton className="h-4 w-8 shrink-0 rounded-sm" />
          </div>
        ))}
      </div>
    </div>
  )
}

export function PanelEmptyState({
  children = "No data yet",
}: {
  children?: ReactNode
}) {
  return (
    <div
      className={`flex items-center justify-center text-sm text-muted-foreground ${PANEL_MIN_HEIGHT_CLASS}`}
    >
      {children}
    </div>
  )
}

// eslint-disable-next-line react-refresh/only-export-components
export function renderFlag(item: ListItem) {
  // Prefer explicit flags when present
  if ("flag" in item && typeof item.flag === "string") {
    return <span aria-hidden>{item.flag}</span>
  }
  if (
    "countryFlag" in item &&
    typeof (item as Record<string, unknown>).countryFlag === "string"
  ) {
    return (
      <span aria-hidden>{(item as Record<string, string>).countryFlag}</span>
    )
  }
  // Derive from country code if available (alpha2 preferred)
  const code = (item.code || item.alpha2 || item.alpha3) as string | undefined
  const flag = flagFromIso2(code)
  return flag ? <span aria-hidden>{flag}</span> : null
}

// eslint-disable-next-line react-refresh/only-export-components
export function formatMetric(metric: string, value: ListItem[keyof ListItem]) {
  const formatter = FORMATTERS[normalizeMetricKey(metric)]
  if (formatter) {
    return formatter(typeof value === "number" ? value : Number(value))
  }
  return value == null ? "—" : String(value)
}

// eslint-disable-next-line react-refresh/only-export-components
export function isPathLike(name: unknown): boolean {
  const s = String(name || "")
  return s.startsWith("/") && !s.startsWith("//")
}

function MetricValueCell({
  item,
  metric,
  meta,
}: {
  item: ListItem
  metric: string
  meta: ListPayload["meta"]
}) {
  const value = readItemMetric(item, metric)
  const comparison = readComparisonMetric(item, metric)
  const change = readComparisonChange(item, metric)
  const direction =
    typeof change === "number" ? topStatChangeDirection(change) : null
  const tone =
    typeof change === "number" ? topStatChangeTone(metric, change) : null

  const arrow =
    typeof change === "number" && direction !== "flat" ? (
      <span
        className={`inline-flex items-center ${
          tone === "good"
            ? "text-emerald-600 dark:text-emerald-400"
            : "text-rose-600 dark:text-rose-400"
        }`}
        aria-hidden="true"
      >
        {direction === "up" ? "↗" : "↘"}
      </span>
    ) : null

  const valueContent = (
    <span className="inline-flex items-center justify-end gap-1.5">
      <span>{formatMetric(metric, value)}</span>
      {arrow}
    </span>
  )

  if (typeof change !== "number" || comparison == null || !meta) {
    return valueContent
  }

  return (
    <Tooltip>
      <TooltipTrigger render={valueContent} />
      <TooltipContent className="max-w-none min-w-44 px-3 py-2">
        <div className="space-y-2 text-left">
          <div className="flex items-start justify-between gap-4">
            <div>
              <div className="font-medium">
                {formatMetric(metric, value)}
                {metricLabelSuffix(metric)}
              </div>
              {meta.dateRangeLabel ? (
                <div className="text-[11px] text-background/70">
                  {meta.dateRangeLabel}
                </div>
              ) : null}
            </div>
            <span
              className={`inline-flex items-center gap-1 text-[11px] font-medium ${
                tone === "good" ? "text-emerald-300" : "text-rose-300"
              }`}
            >
              {direction === "up" ? "▲" : direction === "down" ? "▼" : ""}
              {formatTopStatChangeValue(change)}
            </span>
          </div>
          <div className="border-t border-background/15" />
          <div>
            <div className="font-medium text-background/80">
              {formatMetric(metric, comparison as ListItem[keyof ListItem])}
              {metricLabelSuffix(metric)}
            </div>
            {meta.comparisonDateRangeLabel ? (
              <div className="text-[11px] text-background/70">
                {meta.comparisonDateRangeLabel}
              </div>
            ) : null}
          </div>
        </div>
      </TooltipContent>
    </Tooltip>
  )
}

function metricLabelSuffix(metric: string) {
  const title = METRIC_LABELS[normalizeMetricKey(metric)] ?? metric
  return title.length < 3 ? "" : ` ${title.toLowerCase()}`
}

function readItemMetric(item: ListItem, metric: string) {
  const camelMetric = metric.replace(/_([a-z])/g, (_, c: string) =>
    c.toUpperCase()
  )
  return (
    item[metric] ??
    item[metric as keyof ListItem] ??
    item[camelMetric] ??
    item[camelMetric as keyof ListItem]
  )
}

function readComparisonMetric(item: ListItem, metric: string) {
  const comparison =
    item.comparison && typeof item.comparison === "object"
      ? item.comparison
      : null
  if (!comparison) return undefined

  const camelMetric = metric.replace(/_([a-z])/g, (_, c: string) =>
    c.toUpperCase()
  )
  return (
    (comparison as Record<string, unknown>)[metric] ??
    (comparison as Record<string, unknown>)[camelMetric]
  )
}

function readComparisonChange(item: ListItem, metric: string) {
  const comparison =
    item.comparison && typeof item.comparison === "object"
      ? item.comparison
      : null
  if (!comparison) return undefined

  const change =
    (comparison as Record<string, unknown>).change &&
    typeof (comparison as Record<string, unknown>).change === "object"
      ? ((comparison as Record<string, unknown>).change as Record<
          string,
          unknown
        >)
      : null
  if (!change) return undefined

  const camelMetric = metric.replace(/_([a-z])/g, (_, c: string) =>
    c.toUpperCase()
  )
  const value = change[metric] ?? change[camelMetric]
  return typeof value === "number" && !Number.isNaN(value) ? value : undefined
}
