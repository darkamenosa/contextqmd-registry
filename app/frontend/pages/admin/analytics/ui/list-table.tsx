import type { ReactNode } from "react"
import { ExternalLink } from "lucide-react"

import {
  durationFormatter,
  nullable,
  numberShortFormatter,
  percentageFormatter,
} from "../lib/number-formatter"
import type { ListItem, ListMetricKey, ListPayload } from "../types"

// eslint-disable-next-line react-refresh/only-export-components
export const METRIC_LABELS: Record<ListMetricKey, string> = {
  visitors: "Visitors",
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
  uniques: (value) => numberShortFormatter(value ?? 0),
  total: (value) => numberShortFormatter(value ?? 0),
  percentage: (value) => percentageFormatter(value ?? null),
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

  // Use new DevicesPanel styling when displayBars is false
  if (!displayBars) {
    return (
      <div
        className="overflow-hidden"
        data-testid={testId ? `${testId}-wrap` : undefined}
      >
        <table
          className="min-w-full text-sm"
          data-testid={testId ? `${testId}-table` : undefined}
        >
          <thead>
            <tr className="border-b border-border">
              <th
                scope="col"
                className="pr-3 pb-2 text-left text-xs font-semibold tracking-wide text-muted-foreground uppercase"
              >
                {itemLabel}
              </th>
              <th scope="col" className="pb-2 text-right">
                <div className="flex items-center justify-end gap-8">
                  {metrics.map((metric) => {
                    const title =
                      (metricLabels && metricLabels[metric]) ??
                      METRIC_LABELS[metric] ??
                      metric
                    const len = String(title).length
                    const w =
                      len >= 16 ? 144 : len >= 12 ? 120 : BASE_NUM_COL_MIN_PX
                    return (
                      <span
                        key={metric}
                        className="text-right text-xs font-semibold tracking-wide whitespace-nowrap text-muted-foreground uppercase"
                        style={{ minWidth: w, width: w }}
                      >
                        {title}
                      </span>
                    )
                  })}
                </div>
              </th>
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
                  <td className="" colSpan={2}>
                    {/* Two-layer layout so the bar respects the left content width and doesn't sit under the numbers */}
                    <div className="relative flex items-center justify-between">
                      {/* Left content with its own relative box for the bar; reserve icon column only when present */}
                      <div
                        className={`relative flex min-w-0 flex-1 items-center gap-3 pr-3 ${hasLeading ? "pl-8" : "pl-2"}`}
                      >
                        {/* Background bar sized to left content width */}
                        <div
                          className={`absolute inset-y-[1px] left-0 rounded-xs ${barColor}`}
                          style={{ width: `${barWidth}%` }}
                          aria-hidden="true"
                        />
                        {/* Fixed icon column so bars never overlap icons (only when present) */}
                        {hasLeading ? (
                          <span className="absolute left-1 z-10 inline-flex h-6 w-6 items-center justify-center">
                            {leadingEl}
                          </span>
                        ) : null}
                        <span className="relative z-10 font-medium break-all whitespace-normal text-foreground">
                          <span className="inline-flex items-center gap-1">
                            <span>{item.name}</span>
                            {isPathLike(item.name) ? (
                              <a
                                href={String(item.name)}
                                target="_blank"
                                rel="noopener noreferrer"
                                className="text-muted-foreground opacity-0 transition group-hover:opacity-100 hover:text-foreground"
                                onClick={(e) => e.stopPropagation()}
                                aria-label="Open page in new tab"
                                title="Open page"
                              >
                                <ExternalLink className="h-3.5 w-3.5" />
                              </a>
                            ) : null}
                          </span>
                        </span>
                      </div>
                      {/* Right metrics untouched by the bar */}
                      <div className="flex shrink-0 items-center gap-8">
                        {metrics.map((metric) => {
                          const title =
                            (metricLabels && metricLabels[metric]) ??
                            METRIC_LABELS[metric] ??
                            metric
                          const len = String(title).length
                          const w =
                            len >= 16
                              ? 144
                              : len >= 12
                                ? 120
                                : BASE_NUM_COL_MIN_PX
                          return (
                            <span
                              key={metric}
                              className="text-right font-semibold whitespace-nowrap text-foreground tabular-nums"
                              style={{ minWidth: w, width: w }}
                            >
                              {formatMetric(metric, item[metric])}
                            </span>
                          )
                        })}
                      </div>
                    </div>
                  </td>
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
    <div className="overflow-hidden rounded-xs border">
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
                {METRIC_LABELS[metric] ?? metric}
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
                    <span className="font-medium break-all whitespace-normal text-foreground">
                      <span className="inline-flex items-center gap-1">
                        <span>{item.name}</span>
                        {isPathLike(item.name) ? (
                          <a
                            href={String(item.name)}
                            target="_blank"
                            rel="noopener noreferrer"
                            className="text-muted-foreground opacity-0 transition group-hover:opacity-100 hover:text-foreground"
                            onClick={(e) => e.stopPropagation()}
                            aria-label="Open page in new tab"
                            title="Open page"
                          >
                            <ExternalLink className="h-3.5 w-3.5" />
                          </a>
                        ) : null}
                      </span>
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
                      {formatMetric(metric, item[metric])}
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

function flagFromIso2(code?: string) {
  if (!code) return ""
  const m = String(code)
    .toUpperCase()
    .match(/^[A-Z]{2}$/)
  if (!m) return ""
  const A = 0x1f1e6
  return Array.from(m[0])
    .map((c) => String.fromCodePoint(A + (c.charCodeAt(0) - 65)))
    .join("")
}

// eslint-disable-next-line react-refresh/only-export-components
export function formatMetric(
  metric: ListMetricKey,
  value: ListItem[keyof ListItem]
) {
  const formatter = FORMATTERS[metric]
  if (formatter) {
    return formatter(typeof value === "number" ? value : Number(value))
  }
  return value == null ? "—" : String(value)
}

function isPathLike(name: unknown): boolean {
  const s = String(name || "")
  return s.startsWith("/") && !s.startsWith("//")
}
