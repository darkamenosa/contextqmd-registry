import {
  forwardRef,
  useState,
  type ComponentPropsWithoutRef,
  type ReactNode,
} from "react"
import { ExternalLink } from "lucide-react"

import { Skeleton } from "@/components/ui/skeleton"
import {
  Tooltip,
  TooltipContent,
  TooltipTrigger,
} from "@/components/ui/tooltip"

import { flagFromIso2 } from "../lib/country-flag"
import {
  formatMetric,
  formatMetricLong,
  isMetricAbbreviated,
  metricLabelSuffix,
  resolveMetricLabel,
  type MetricLabelMap,
} from "../lib/metric-display"
import { normalizeMetricKey } from "../lib/metric-key"
import {
  formatTopStatChangeValue,
  topStatChangeDirection,
  topStatChangeTone,
} from "../lib/top-stat-change"
import type { ListItem, ListMetricKey, ListPayload } from "../types"

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
  revealSecondaryMetricsOnHover = false,
  testId,
}: MetricTableProps) {
  const metrics = data.metrics
  const resolvedMetricLabels = metricLabels ?? data.meta.metricLabels
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
  const compactMetricLabel = (metric: string) =>
    resolveMetricLabel(metric, resolvedMetricLabels, {
      compactPercentage: true,
    })
  const metricHasComparisonSlot = Object.fromEntries(
    metrics.map((metric) => [
      metric,
      hasVisibleMetricComparison(data.results, metric),
    ])
  ) as Record<string, boolean>
  const metricWidth = (metric: string) => {
    const normalizedMetric = normalizeMetricKey(metric)
    const title = compactMetricLabel(metric)
    const comparisonSlotWidth = metricHasComparisonSlot[metric]
      ? COMPARISON_ICON_SLOT_PX
      : 0
    const metricFloor: Partial<Record<ListMetricKey, number>> = {
      visitors: 72,
      clicks: 72,
      events: 72,
      visits: 72,
      uniques: 72,
      total: 72,
      pageviews: 72,
      impressions: 72,
      percentage: 64,
      ctr: 64,
      position: 72,
      conversionRate: 88,
      bounceRate: 88,
      exitRate: 88,
      scrollDepth: 88,
      visitDuration: 96,
      timeOnPage: 96,
    }
    const labelWidth =
      Math.ceil(String(title).length * 9) + comparisonSlotWidth + 18
    const valueWidth =
      Math.max(
        0,
        ...data.results.map(
          (item) =>
            String(formatMetric(metric, readItemMetric(item, metric))).length
        )
      ) *
        11 +
      comparisonSlotWidth +
      18

    return Math.max(
      metricFloor[normalizedMetric] ?? BASE_NUM_COL_MIN_PX,
      labelWidth,
      valueWidth
    )
  }
  // Use new DevicesPanel styling when displayBars is false
  const [hoveredRow, setHoveredRow] = useState<string | null>(null)
  const [isReportHovered, setIsReportHovered] = useState(false)
  const hoverRevealMetrics = revealSecondaryMetricsOnHover
    ? metrics.filter((metric) => normalizeMetricKey(metric) === "percentage")
    : []
  const alwaysVisibleMetrics = metrics.filter(
    (metric) => !hoverRevealMetrics.includes(metric)
  )
  if (!displayBars) {
    const visibleMetrics =
      alwaysVisibleMetrics.length > 0 ? alwaysVisibleMetrics : metrics
    const orderedMetrics = [...visibleMetrics, ...hoverRevealMetrics]
    const leadingNodes = data.results.map((item) =>
      renderLeading ? renderLeading(item) : renderFlag(item)
    )
    const reserveLeadingSlot = leadingNodes.some(Boolean)
    const reportExpanded = isReportHovered
    const firstHoverMetricIndex = orderedMetrics.findIndex((metric) =>
      hoverRevealMetrics.includes(metric)
    )
    const compactGridTemplate = [
      "minmax(0, 1fr)",
      ...orderedMetrics.map((metric) => {
        const isHoverMetric = hoverRevealMetrics.includes(metric)
        const width = isHoverMetric && !reportExpanded ? 0 : metricWidth(metric)
        return `${width}px`
      }),
    ].join(" ")

    return (
      <div
        className={`group/report overflow-hidden ${PANEL_MIN_HEIGHT_CLASS}`}
        data-testid={testId ? `${testId}-wrap` : undefined}
        onMouseEnter={() => setIsReportHovered(true)}
        onMouseLeave={() => setIsReportHovered(false)}
      >
        <div
          className="grid items-center border-b border-border pb-2 transition-[grid-template-columns] duration-150 ease-out"
          style={{ gridTemplateColumns: compactGridTemplate }}
        >
          <span
            className={`min-w-0 pr-3 text-left text-xs font-semibold tracking-wide text-muted-foreground uppercase ${reserveLeadingSlot ? "pl-8" : "pl-2"}`}
          >
            {itemLabel}
          </span>
          {orderedMetrics.map((metric) => {
            const isHoverMetric = hoverRevealMetrics.includes(metric)
            const slidesForHover =
              firstHoverMetricIndex !== -1 &&
              !isHoverMetric &&
              orderedMetrics.indexOf(metric) < firstHoverMetricIndex

            return (
              <span
                key={metric}
                className={`min-w-0 overflow-hidden text-xs font-semibold tracking-wide whitespace-nowrap text-muted-foreground uppercase transition-all duration-150 ease-out ${slidesForHover ? "transition-transform duration-150 ease-out" : ""} ${slidesForHover && !reportExpanded ? "translate-x-0" : "translate-x-0"} ${isHoverMetric && !reportExpanded ? "translate-x-full opacity-0" : "translate-x-0 opacity-100"}`}
              >
                <MetricHeaderCell
                  label={compactMetricLabel(metric)}
                  reserveComparisonSlot={metricHasComparisonSlot[metric]}
                />
              </span>
            )
          })}
        </div>

        <div className="divide-y divide-border/50">
          {data.results.map((item, index) => {
            const value = Number(item[barMetric] ?? 0)
            const barWidth = Math.max((value / maxValue) * 100, 0)
            const colors = colorMap[barColorTheme]
            const barColor =
              index === 0 ? colors[0] : index === 1 ? colors[1] : colors[2]
            const leadingEl = leadingNodes[index]
            const hasLeading = Boolean(leadingEl)
            const isHovered = hoveredRow === item.name

            return (
              <div
                key={item.name}
                className={`group/row grid h-9 items-center transition-[grid-template-columns,background-color] duration-150 ease-out ${onRowClick ? "cursor-pointer hover:bg-muted/30" : ""}`}
                style={{ gridTemplateColumns: compactGridTemplate }}
                onClick={() => onRowClick?.(item)}
                onMouseEnter={() => setHoveredRow(item.name)}
                onMouseLeave={() =>
                  setHoveredRow((current) =>
                    current === item.name ? null : current
                  )
                }
                data-testid={testId ? `${testId}-row` : undefined}
                data-name={String(item.name)}
              >
                <div className="min-w-0 overflow-hidden pr-3">
                  <div
                    className={`relative flex min-w-0 items-center gap-3 ${reserveLeadingSlot ? "pl-8" : "pl-2"}`}
                  >
                    <div
                      className={`absolute inset-y-[1px] left-0 rounded-xs transition-colors duration-150 ${barColor} ${isHovered ? "bg-primary/18" : ""}`}
                      style={{ width: `${barWidth}%` }}
                      aria-hidden="true"
                    />
                    {reserveLeadingSlot ? (
                      <span className="absolute left-1 z-10 inline-flex size-6 items-center justify-center">
                        {hasLeading ? leadingEl : null}
                      </span>
                    ) : null}
                    <span className="relative z-10 flex min-w-0 flex-1 items-center gap-1 text-sm font-normal text-foreground">
                      <span className="truncate" title={String(item.name)}>
                        {item.name}
                      </span>
                      {isPathLike(item.name) ? (
                        <a
                          href={String(item.name)}
                          target="_blank"
                          rel="noopener noreferrer"
                          className="shrink-0 text-muted-foreground opacity-0 transition-opacity duration-150 group-hover/row:opacity-100 hover:text-foreground"
                          onClick={(e) => e.stopPropagation()}
                          aria-label="Open page in new tab"
                          title={String(item.name)}
                        >
                          <ExternalLink className="size-3.5" />
                        </a>
                      ) : null}
                    </span>
                  </div>
                </div>

                {orderedMetrics.map((metric, metricIndex) => {
                  const isHoverMetric = hoverRevealMetrics.includes(metric)
                  const slidesForHover =
                    firstHoverMetricIndex !== -1 &&
                    !isHoverMetric &&
                    metricIndex < firstHoverMetricIndex

                  return (
                    <span
                      key={`${item.name}-${metric}`}
                      className={`min-w-0 overflow-hidden text-sm font-normal whitespace-nowrap tabular-nums transition-all duration-150 ease-out ${metricIndex === 0 ? "text-foreground" : "text-muted-foreground"} ${slidesForHover ? "transition-transform duration-150 ease-out" : ""} ${slidesForHover && reportExpanded ? "-translate-x-0.5" : "translate-x-0"} ${isHoverMetric ? "group-hover/row:text-foreground" : ""} ${isHoverMetric && !reportExpanded ? "translate-x-full opacity-0" : "translate-x-0 opacity-100"}`}
                    >
                      <MetricValueCell
                        item={item}
                        metric={metric}
                        meta={data.meta}
                        metricLabels={resolvedMetricLabels}
                        reserveComparisonSlot={metricHasComparisonSlot[metric]}
                      />
                    </span>
                  )
                })}
              </div>
            )
          })}
        </div>

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
                <MetricHeaderCell
                  label={resolveMetricLabel(metric, resolvedMetricLabels)}
                  reserveComparisonSlot={metricHasComparisonSlot[metric]}
                />
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
                    <span className="flex min-w-0 flex-1 items-center gap-1 font-normal text-foreground">
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
                        metricLabels={resolvedMetricLabels}
                        reserveComparisonSlot={metricHasComparisonSlot[metric]}
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
const COMPARISON_ICON_SLOT_PX = 14
const COMPACT_METRIC_INNER_STYLE = {
  gridTemplateColumns: `minmax(0, 1fr) ${COMPARISON_ICON_SLOT_PX}px`,
} as React.CSSProperties
const COMPACT_METRIC_SINGLE_STYLE = {
  gridTemplateColumns: "minmax(0, 1fr)",
} as React.CSSProperties

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
              className="h-5 rounded-xs"
              style={{
                width: `${SKELETON_BAR_WIDTHS[i % SKELETON_BAR_WIDTHS.length]}%`,
              }}
            />
            <Skeleton className="h-4 w-8 shrink-0 rounded-xs" />
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

function hasVisibleMetricComparison(items: ListItem[], metric: string) {
  return items.some((item) => {
    const change = readComparisonChange(item, metric)
    return (
      typeof change === "number" && topStatChangeDirection(change) !== "flat"
    )
  })
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
  metricLabels,
  reserveComparisonSlot = false,
}: {
  item: ListItem
  metric: string
  meta: ListPayload["meta"]
  metricLabels?: MetricLabelMap
  reserveComparisonSlot?: boolean
}) {
  const value = readItemMetric(item, metric)
  const comparison = readComparisonMetric(item, metric)
  const change = readComparisonChange(item, metric)
  const direction =
    typeof change === "number" ? topStatChangeDirection(change) : null
  const tone =
    typeof change === "number" ? topStatChangeTone(metric, change) : null
  const arrowGlyph =
    direction === "up" ? "↗" : direction === "down" ? "↘" : null
  const shortValue = formatMetric(metric, value)
  const longValue = formatMetricLong(metric, value)
  const longComparisonValue =
    comparison == null
      ? null
      : formatMetricLong(metric, comparison as ListItem[keyof ListItem])
  const isAbbreviated = isMetricAbbreviated(metric, value)
  const labelSuffix = metricLabelSuffix(metric, metricLabels)

  const arrow =
    typeof change === "number" && direction !== "flat" && arrowGlyph ? (
      <span
        className={`inline-flex items-center ${
          tone === "good"
            ? "text-emerald-600 dark:text-emerald-400"
            : "text-rose-600 dark:text-rose-400"
        }`}
        aria-hidden="true"
      >
        {arrowGlyph}
      </span>
    ) : null

  const valueContent = (
    <MetricCellFrame
      reserveComparisonSlot={reserveComparisonSlot}
      trailingSlot={
        reserveComparisonSlot ? (
          <span
            className={`inline-flex w-3.5 items-center justify-center ${arrow ? "" : "invisible"}`}
            aria-hidden="true"
          >
            {arrow ?? "↗"}
          </span>
        ) : null
      }
    >
      <span className="min-w-0 text-right">{shortValue}</span>
    </MetricCellFrame>
  )

  const shouldShowComparisonTooltip =
    typeof change === "number" && comparison != null && !!meta

  if (!shouldShowComparisonTooltip && !isAbbreviated) {
    return valueContent
  }

  if (!shouldShowComparisonTooltip) {
    return (
      <MetricCellFrame
        reserveComparisonSlot={reserveComparisonSlot}
        trailingSlot={
          reserveComparisonSlot ? (
            <span
              className="invisible inline-flex w-3.5 items-center justify-center"
              aria-hidden="true"
            >
              ↗
            </span>
          ) : null
        }
      >
        <Tooltip disableHoverablePopup>
          <TooltipTrigger
            render={
              <span className="inline-flex w-fit min-w-0 items-center justify-end text-right">
                {shortValue}
              </span>
            }
          />
          <TooltipContent
            sideOffset={6}
            className="pointer-events-none max-w-none px-3 py-2"
          >
            <div className="text-left font-medium whitespace-nowrap">
              {longValue}
            </div>
          </TooltipContent>
        </Tooltip>
      </MetricCellFrame>
    )
  }

  return (
    <Tooltip disableHoverablePopup>
      <TooltipTrigger render={valueContent} />
      <TooltipContent
        sideOffset={6}
        className="pointer-events-none max-w-none min-w-44 px-3 py-2"
      >
        {shouldShowComparisonTooltip ? (
          <div className="space-y-2 text-left">
            <div className="flex items-start justify-between gap-4">
              <div>
                <div className="font-medium">
                  {longValue}
                  {labelSuffix}
                </div>
                {meta.dateRangeLabel ? (
                  <div className="text-[11px] text-background/70">
                    {meta.dateRangeLabel}
                  </div>
                ) : null}
              </div>
              <span
                className={`inline-flex items-center gap-1 text-[11px] font-medium ${
                  tone === "good"
                    ? "text-emerald-300"
                    : tone === "bad"
                      ? "text-rose-300"
                      : "text-background/70"
                }`}
              >
                {direction === "up" ? "▲" : direction === "down" ? "▼" : ""}
                {formatTopStatChangeValue(change)}
              </span>
            </div>
            <div className="border-t border-background/15" />
            <div>
              <div className="font-medium text-background/80">
                {longComparisonValue}
                {labelSuffix}
              </div>
              {meta.comparisonDateRangeLabel ? (
                <div className="text-[11px] text-background/70">
                  {meta.comparisonDateRangeLabel}
                </div>
              ) : null}
            </div>
          </div>
        ) : (
          <div className="text-left font-medium whitespace-nowrap">
            {longValue}
          </div>
        )}
      </TooltipContent>
    </Tooltip>
  )
}

function MetricHeaderCell({
  label,
  reserveComparisonSlot = false,
}: {
  label: string
  reserveComparisonSlot?: boolean
}) {
  return (
    <MetricCellFrame
      className="text-muted-foreground"
      reserveComparisonSlot={reserveComparisonSlot}
      trailingSlot={
        reserveComparisonSlot ? (
          <span
            className="invisible inline-flex w-3.5 items-center justify-center"
            aria-hidden="true"
          >
            ↗
          </span>
        ) : null
      }
    >
      <span className="min-w-0 text-right">{label}</span>
    </MetricCellFrame>
  )
}

const MetricCellFrame = forwardRef<
  HTMLSpanElement,
  {
    children: ReactNode
    trailingSlot?: ReactNode
    reserveComparisonSlot?: boolean
  } & ComponentPropsWithoutRef<"span">
>(function MetricCellFrame(
  {
    children,
    trailingSlot,
    className,
    reserveComparisonSlot = false,
    style,
    ...props
  },
  ref
) {
  return (
    <span
      ref={ref}
      className={`grid w-full min-w-0 items-center justify-items-end gap-1.5 ${className ?? ""}`}
      style={{
        ...(reserveComparisonSlot
          ? COMPACT_METRIC_INNER_STYLE
          : COMPACT_METRIC_SINGLE_STYLE),
        ...style,
      }}
      {...props}
    >
      {children}
      {reserveComparisonSlot ? trailingSlot : null}
    </span>
  )
})

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
