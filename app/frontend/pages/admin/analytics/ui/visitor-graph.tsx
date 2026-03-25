import {
  startTransition,
  useCallback,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react"
import {
  CategoryScale,
  Chart as ChartJS,
  Tooltip as ChartTooltip,
  Filler,
  Legend,
  LinearScale,
  LineElement,
  PointElement,
  Title,
  type ChartDataset,
} from "chart.js"
import dayjs from "dayjs"
import timezone from "dayjs/plugin/timezone"
import utc from "dayjs/plugin/utc"
import { ChevronDown } from "lucide-react"
import { Line } from "react-chartjs-2"

import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { Skeleton } from "@/components/ui/skeleton"

// Tooltip imports removed (sampling tooltip currently commented out)

import { fetchMainGraph, fetchTopStats } from "../api"
import { useLastLoadContext } from "../last-load-context"
import {
  getGraphIntervalFromSearch,
  getGraphMetricFromSearch,
} from "../lib/dashboard-url-state"
import { useScopedQuery } from "../lib/query-scope"
import {
  formatTopStatChangeValue,
  topStatChangeDirection,
  topStatChangeTone,
} from "../lib/top-stat-change"
import { useQueryContext } from "../query-context"
import { useSiteContext } from "../site-context"
import { useTopStatsContext } from "../top-stats-context"
import type { MainGraphPayload, TopStat } from "../types"

dayjs.extend(utc)
dayjs.extend(timezone)

ChartJS.register(
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  Title,
  ChartTooltip,
  Legend,
  Filler
)

const INTERVAL_LABELS: Record<string, string> = {
  minute: "Minutes",
  hour: "Hours",
  day: "Days",
  week: "Weeks",
  month: "Months",
}

const STORAGE_PREFIX = "admin.analytics"

// Detect if user prefers 12-hour clock
function is12HourClock(): boolean {
  if (typeof navigator === "undefined") return false
  const browserFormat = new Intl.DateTimeFormat(navigator.language, {
    hour: "numeric",
  })
  return browserFormat.resolvedOptions().hour12 ?? false
}

function resolvePreferredMetric(
  graphableMetrics: string[],
  siteDomain: string,
  fallbackMetric: string,
  requestedMetric?: string | null
) {
  if (requestedMetric && graphableMetrics.includes(requestedMetric)) {
    return requestedMetric
  }
  if (typeof window === "undefined") return fallbackMetric
  const stored = localStorage.getItem(`${STORAGE_PREFIX}.${siteDomain}.metric`)
  if (stored && graphableMetrics.includes(stored)) {
    return stored
  }
  return fallbackMetric
}

function availableIntervalsForPeriod(period: string) {
  switch (period) {
    case "realtime":
      return ["minute"]
    case "day":
      return ["minute", "hour"]
    case "7d":
      return ["hour", "day"]
    case "28d":
    case "30d":
      return ["day", "week"]
    case "91d":
      return ["day", "week", "month"]
    case "month":
      return ["day", "week"]
    case "12mo":
    case "year":
    case "all":
    case "custom":
      return ["day", "week", "month"]
    default:
      return ["day"]
  }
}

function resolvePreferredInterval(
  period: string,
  siteDomain: string,
  fallbackInterval: string,
  requestedInterval?: string | null
) {
  const options = availableIntervalsForPeriod(period)
  if (requestedInterval && options.includes(requestedInterval)) {
    return requestedInterval
  }
  if (typeof window !== "undefined") {
    const stored = localStorage.getItem(
      `${STORAGE_PREFIX}.${siteDomain}.interval`
    )
    if (stored && options.includes(stored)) {
      return stored
    }
  }
  if (options.includes(fallbackInterval)) {
    return fallbackInterval
  }
  return options[0] ?? fallbackInterval
}

// Date formatting utilities matching Plausible's exact logic
function formatHour(isoDate: string, tz: string): string {
  const date = dayjs.utc(isoDate).tz(tz)
  if (is12HourClock()) {
    return date.format("ha") // "3pm", "12am"
  } else {
    return date.format("HH:mm") // "15:00", "00:00"
  }
}

function formatDay(isoDate: string, includeYear: boolean, tz: string): string {
  const date = dayjs.utc(isoDate).tz(tz)
  if (includeYear) {
    return date.format("D MMM YY") // "5 Oct 25"
  } else {
    return date.format("D MMM") // "5 Oct"
  }
}

function formatMonth(isoDate: string, tz: string): string {
  const date = dayjs.utc(isoDate).tz(tz)
  return date.format("MMMM YYYY") // "October 2025"
}

function hasMultipleYears(labels: string[]): boolean {
  const years = labels
    .filter((label) => typeof label === "string")
    .map((label) => label.split("-")[0])
  return new Set(years).size > 1
}

type VisitorGraphProps = {
  initialGraph: MainGraphPayload
}

export default function VisitorGraph({ initialGraph }: VisitorGraphProps) {
  const { query, search } = useQueryContext()
  const { payload, update } = useTopStatsContext()
  const { touch } = useLastLoadContext()
  const site = useSiteContext()

  const [graph, setGraph] = useState<MainGraphPayload>(initialGraph)
  const [loading, setLoading] = useState(false)
  const abortRef = useRef<AbortController | null>(null)
  const { value: baseQuery } = useScopedQuery(query, {
    omitMetric: true,
    omitInterval: true,
  })
  const didFetchTopStatsRef = useRef(false)
  const didFetchGraphRef = useRef(false)

  const graphableMetrics = payload.graphableMetrics
  const availableIntervals = useMemo(
    () => availableIntervalsForPeriod(query.period),
    [query.period]
  )
  const requestedMetric = getGraphMetricFromSearch(search, initialGraph.metric)
  const requestedInterval = getGraphIntervalFromSearch(
    search,
    initialGraph.interval
  )
  const [selectedMetric, setSelectedMetric] = useState(() =>
    resolvePreferredMetric(
      payload.graphableMetrics,
      site.domain,
      initialGraph.metric,
      requestedMetric
    )
  )
  const [selectedInterval, setSelectedInterval] = useState(() =>
    resolvePreferredInterval(
      query.period,
      site.domain,
      initialGraph.interval,
      requestedInterval
    )
  )

  const effectiveMetric = useMemo(() => {
    if (graphableMetrics.includes(selectedMetric)) return selectedMetric
    return (
      resolvePreferredMetric(
        graphableMetrics,
        site.domain,
        graphableMetrics[0] ?? initialGraph.metric
      ) || initialGraph.metric
    )
  }, [graphableMetrics, initialGraph.metric, selectedMetric, site.domain])

  const effectiveInterval = useMemo(() => {
    if (availableIntervals.includes(selectedInterval)) return selectedInterval
    return resolvePreferredInterval(
      query.period,
      site.domain,
      initialGraph.interval
    )
  }, [
    availableIntervals,
    initialGraph.interval,
    query.period,
    selectedInterval,
    site.domain,
  ])

  const fetchGraphData = useCallback(
    async (
      nextMetric: string,
      nextInterval: string,
      controller: AbortController
    ) => {
      return fetchMainGraph(
        baseQuery,
        { metric: nextMetric, interval: nextInterval },
        controller.signal
      )
    },
    [baseQuery]
  )

  useEffect(() => {
    if (!didFetchTopStatsRef.current) {
      didFetchTopStatsRef.current = true
      return
    }

    const controller = new AbortController()

    fetchTopStats(baseQuery, controller.signal)
      .then((data) => {
        update(data)
        touch()
      })
      .catch((error) => {
        if (error.name !== "AbortError") {
          console.error(error)
        }
      })

    return () => controller.abort()
  }, [baseQuery, touch, update])

  useEffect(() => {
    if (!didFetchGraphRef.current) {
      didFetchGraphRef.current = true
      if (
        effectiveMetric === initialGraph.metric &&
        effectiveInterval === initialGraph.interval
      ) {
        return
      }
    }

    const controller = new AbortController()
    abortRef.current?.abort()
    abortRef.current = controller
    startTransition(() => setLoading(true))

    fetchGraphData(effectiveMetric, effectiveInterval, controller)
      .then((data) => {
        setGraph(data)
      })
      .catch((error) => {
        if (error.name !== "AbortError") {
          console.error(error)
        }
      })
      .finally(() => {
        startTransition(() => setLoading(false))
      })

    return () => controller.abort()
  }, [
    baseQuery,
    effectiveInterval,
    effectiveMetric,
    fetchGraphData,
    initialGraph.interval,
    initialGraph.metric,
  ])

  const changeMetric = useCallback(
    (next: string) => {
      if (next === effectiveMetric) return
      localStorage.setItem(`${STORAGE_PREFIX}.${site.domain}.metric`, next)
      setSelectedMetric(next)
    },
    [effectiveMetric, site.domain]
  )

  const changeInterval = useCallback(
    (nextInterval: string) => {
      if (nextInterval === effectiveInterval) return
      localStorage.setItem(
        `${STORAGE_PREFIX}.${site.domain}.interval`,
        nextInterval
      )
      setSelectedInterval(nextInterval)
    },
    [effectiveInterval, site.domain]
  )

  const chartData = useMemo(() => createChartData(graph), [graph])
  const chartOptions = useMemo(
    () => createChartOptions(graph, query.period, site.timezone),
    [graph, query.period, site.timezone]
  )

  return (
    <section className="rounded-lg border border-border bg-card">
      <div className="space-y-3 p-4">
        <TopStatsGrid
          stats={payload.topStats}
          graphableMetrics={graphableMetrics}
          selectedMetric={effectiveMetric}
          onSelectMetric={changeMetric}
          comparingFrom={payload.comparingFrom}
          comparingTo={payload.comparingTo}
          period={query.period}
          timezone={site.timezone}
          showComparison={Boolean(query.comparison && payload.comparingFrom)}
          primaryFrom={payload.from}
          primaryTo={payload.to}
        />

        <div className="relative">
          {loading && (
            <div className="absolute inset-0 z-10 flex items-center justify-center rounded-xs bg-card/75 backdrop-blur-xs">
              <Spinner />
            </div>
          )}
          <div className="flex justify-end gap-2 pb-2">
            <IntervalPicker
              interval={effectiveInterval}
              onChange={changeInterval}
            />
          </div>
          <div className="h-56">
            <Line options={chartOptions} data={chartData} />
          </div>
        </div>
      </div>
    </section>
  )
}

function Spinner() {
  return (
    <div className="flex items-center gap-2 text-sm text-muted-foreground">
      <Skeleton className="size-6 rounded-full" />
      Loading…
    </div>
  )
}

type ChartPoint = number | null

function splitPrimaryPlot(
  plot: number[],
  presentIndex?: number | null
): {
  solidPlot: ChartPoint[]
  dashedPlot: ChartPoint[] | null
} {
  if (
    presentIndex == null ||
    presentIndex <= 0 ||
    presentIndex >= plot.length
  ) {
    return { solidPlot: plot, dashedPlot: null }
  }

  return {
    solidPlot: plot.slice(0, presentIndex),
    dashedPlot: Array.from<ChartPoint>({ length: presentIndex - 1 }).concat(
      plot.slice(presentIndex - 1, presentIndex + 1)
    ),
  }
}

function createChartData(graph: MainGraphPayload) {
  // Chart palette — rgba equivalents of --primary (oklch 0.205 0 0 ≈ #1a1a1a)
  const PRIMARY_STROKE = "rgba(26, 26, 26, 1)"
  const PRIMARY_FILL_START = "rgba(26, 26, 26, 0.06)"
  const COMP_STROKE = "rgba(120, 120, 120, 0.7)"
  const COMP_POINT = COMP_STROKE
  const COMP_POINT_HOVER = "rgba(128, 128, 128, 0.7)"

  const { solidPlot, dashedPlot } = splitPrimaryPlot(
    graph.plot,
    graph.presentIndex
  )

  const datasets: ChartDataset<"line", ChartPoint[]>[] = [
    {
      label: graph.metric,
      data: solidPlot,
      borderColor: PRIMARY_STROKE,
      backgroundColor: (context) => {
        const ctx = context.chart.ctx
        const gradient = ctx.createLinearGradient(0, 0, 0, 300)
        gradient.addColorStop(0, PRIMARY_FILL_START)
        gradient.addColorStop(1, "rgba(26, 26, 26, 0)")
        return gradient
      },
      tension: 0, // Straight lines, not curved
      fill: true,
      pointRadius: 0,
      pointBackgroundColor: PRIMARY_STROKE,
      pointHoverBackgroundColor: "rgba(26, 26, 26, 0.7)",
      pointBorderColor: "transparent",
      pointHoverRadius: 3,
      borderWidth: 2,
    },
  ]

  if (dashedPlot) {
    datasets.push({
      label: `${graph.metric}-present`,
      data: dashedPlot,
      borderDash: [3, 3],
      borderColor: PRIMARY_STROKE,
      backgroundColor: (context) => {
        const ctx = context.chart.ctx
        const gradient = ctx.createLinearGradient(0, 0, 0, 300)
        gradient.addColorStop(0, PRIMARY_FILL_START)
        gradient.addColorStop(1, "rgba(26, 26, 26, 0)")
        return gradient
      },
      tension: 0,
      fill: true,
      pointRadius: 0,
      pointBackgroundColor: PRIMARY_STROKE,
      pointHoverBackgroundColor: "rgba(26, 26, 26, 0.7)",
      pointBorderColor: "transparent",
      pointHoverRadius: 3,
      borderWidth: 2,
    })
  }

  if (graph.comparisonPlot) {
    datasets.push({
      label: "Comparison",
      data: graph.comparisonPlot,
      borderColor: COMP_STROKE,
      backgroundColor: "transparent",
      tension: 0,
      pointRadius: 0,
      pointBackgroundColor: COMP_POINT,
      pointHoverBackgroundColor: COMP_POINT_HOVER,
      pointBorderColor: "transparent",
      pointHoverRadius: 3,
      fill: false,
      borderWidth: 2,
      yAxisID: "y", // Use same y-axis
    })
  }

  return {
    labels: graph.labels,
    datasets,
  }
}

function createChartOptions(
  graph: MainGraphPayload,
  period: string,
  tz: string
) {
  const METRIC_LABELS: Record<string, string> = {
    visitors: "Visitors",
    visits: "Visits",
    pageviews: "Pageviews",
    events: "Conversions",
    views_per_visit: "Views per visit",
    bounce_rate: "Bounce rate",
    visit_duration: "Visit duration",
    conversion_rate: "Conversion rate",
    scroll_depth: "Scroll depth",
    time_on_page: "Time on page",
  }
  const metricFormatter = (val: number): string => {
    const m = graph.metric
    if (m === "visit_duration" || m === "time_on_page")
      return durationFormatter(val)
    if (m === "bounce_rate" || m === "conversion_rate" || m === "scroll_depth")
      return `${val.toFixed(2)}%`
    if (m === "views_per_visit") return val.toFixed(2)
    return numberShortFormatter(val)
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const externalTooltip = (ctx: any) => {
    const { chart, tooltip } = ctx
    let el = chart.canvas.parentNode.querySelector(
      ".analytics-tooltip"
    ) as HTMLDivElement | null
    if (!el) {
      el = document.createElement("div")
      el.className = "analytics-tooltip"
      el.style.position = "absolute"
      el.style.pointerEvents = "none"
      el.style.backgroundColor = "var(--popover)"
      el.style.border = "1px solid var(--border)"
      el.style.borderRadius = "10px"
      el.style.padding = "10px 12px"
      el.style.color = "var(--popover-foreground)"
      el.style.zIndex = "60"
      el.style.minWidth = "220px"
      el.style.boxShadow = "0 4px 12px oklch(0 0 0 / 0.1)"
      chart.canvas.parentNode.appendChild(el)
    }

    if (tooltip.opacity === 0) {
      el.style.opacity = "0"
      return
    }

    const idx = tooltip.dataPoints?.[0]?.dataIndex ?? 0
    const labelISO = graph.labels[idx]
    const comparisonISO = graph.comparisonLabels?.[idx]

    const shouldShowYear = hasMultipleYears(graph.labels)
    const baseTitle = METRIC_LABELS[graph.metric] || graph.metric

    const fmtPrimary = (() => {
      if (!labelISO) return ""
      if (graph.interval === "hour")
        return `${formatDay(labelISO, shouldShowYear, tz)}, ${formatHour(labelISO, tz)}`
      if (graph.interval === "minute") return formatHour(labelISO, tz)
      if (graph.interval === "month") return formatMonth(labelISO, tz)
      return formatDay(labelISO, shouldShowYear, tz)
    })()

    const fmtComparison = (() => {
      if (!comparisonISO) return null
      if (graph.interval === "hour")
        return `${formatDay(comparisonISO, hasMultipleYears(graph.comparisonLabels || []), tz)}, ${formatHour(comparisonISO, tz)}`
      if (graph.interval === "minute") return formatHour(comparisonISO, tz)
      if (graph.interval === "month") return formatMonth(comparisonISO, tz)
      return formatDay(
        comparisonISO,
        hasMultipleYears(graph.comparisonLabels || []),
        tz
      )
    })()

    const currentVal = Number(graph.plot[idx] ?? 0)
    const comparisonVal = graph.comparisonPlot
      ? Number(graph.comparisonPlot[idx] ?? 0)
      : null
    const changePct =
      comparisonVal && comparisonVal !== 0
        ? ((currentVal - comparisonVal) / comparisonVal) * 100
        : null

    const up = changePct != null && changePct >= 0
    const changeStr =
      changePct == null
        ? ""
        : `${up ? "▲" : "▼"} ${Math.round(Math.abs(changePct))}%`
    const changeColor = up
      ? "oklch(0.765 0.177 163.223)"
      : "oklch(0.637 0.237 25.331)"

    // Colors based on datasets
    const ds = (chart.config.data.datasets || []) as ChartDataset<
      "line",
      ChartPoint[]
    >[]
    const primaryDataset =
      ds.find((dataset) => dataset.label !== "Comparison") ?? ds[0]
    const comparisonDataset = ds.find(
      (dataset) => dataset.label === "Comparison"
    )
    const primaryColor =
      (primaryDataset?.borderColor as string) || "rgba(26, 26, 26, 1)"
    const compColor =
      (comparisonDataset?.borderColor as string) || "rgba(128, 128, 128, 0.75)"

    const primaryValStr = metricFormatter(currentVal)
    const compValStr =
      comparisonVal == null ? null : metricFormatter(comparisonVal)

    el.innerHTML = `
      <div style="display:flex;align-items:center;gap:12px;margin-bottom:6px;">
        <div style="font-weight:800;font-size:16px;line-height:1.2;color:var(--foreground);">${baseTitle}</div>
        ${changePct == null ? "" : `<div style="margin-left:auto;font-weight:600;color:${changeColor};">${changeStr}</div>`}
      </div>
      <div style="display:grid;grid-template-columns:auto 1fr auto;gap:6px 10px;align-items:center;">
        <span style="width:10px;height:10px;border-radius:50%;background:${primaryColor};display:inline-block"></span>
        <div style="color:var(--muted-foreground);font-size:13px;">${fmtPrimary}</div>
        <div style="font-weight:800;font-size:16px;color:var(--foreground);">${primaryValStr}</div>
        ${
          compValStr != null
            ? `
          <span style="width:10px;height:10px;border-radius:50%;background:${compColor};display:inline-block;opacity:0.7"></span>
          <div style="color:var(--muted-foreground);font-size:13px;">${fmtComparison}</div>
          <div style="font-weight:800;font-size:16px;color:var(--foreground);opacity:0.85;">${compValStr}</div>
        `
            : ""
        }
      </div>
    `

    const parent = chart.canvas.parentNode as HTMLElement
    const { offsetLeft: positionX, offsetTop: positionY } = chart.canvas
    el.style.opacity = "1"

    // Position tooltip top-left corner at mouse cursor
    let left = positionX + tooltip.caretX
    let top = positionY + tooltip.caretY

    // Clamp to container bounds
    const minX = 6
    const maxX = parent.clientWidth - el.offsetWidth - 6
    const minY = 6
    const maxY = parent.clientHeight - el.offsetHeight - 6
    if (left < minX) left = minX
    if (left > maxX) left = maxX
    if (top < minY) top = minY
    if (top > maxY) top = maxY
    el.style.left = left + "px"
    el.style.top = top + "px"
  }

  return {
    responsive: true,
    maintainAspectRatio: false,
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    onHover: (_event: any, _activeElements: any, chart: any) => {
      // Change cursor to pointer when hovering over chart
      chart.canvas.style.cursor = "pointer"
    },
    interaction: {
      mode: "index" as const,
      intersect: false,
    },
    plugins: {
      legend: { display: false },
      tooltip: {
        enabled: false,
        external: externalTooltip,
      },
    },
    scales: {
      y: {
        beginAtZero: true,
        border: { display: false },
        ticks: {
          maxTicksLimit: 4,
          precision: 0,
          color: "rgba(122, 122, 122, 1)",
          padding: 8,
          callback: function (value: number | string) {
            const num = Number(value)
            if (graph.metric === "views_per_visit")
              return String(Math.round(num))
            return metricFormatter(num)
          },
        },
        grid: {
          color: "rgba(0, 0, 0, 0.04)",
        },
      },
      x: {
        border: { display: false },
        ticks: {
          maxRotation: 0,
          maxTicksLimit: 8,
          autoSkip: true,
          autoSkipPadding: 20,
          color: "rgba(122, 122, 122, 1)",
          callback: function (val: number | string) {
            // Use Chart.js label mapping like Plausible
            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            const scale = this as any
            const label: string = scale.getLabelForValue(val)
            if (!label || label === "__blank__") return ""

            const shouldShowYear = hasMultipleYears(graph.labels)

            if (graph.interval === "hour" && period !== "day") {
              const d = formatDay(label, shouldShowYear, tz)
              const h = formatHour(label, tz)
              return `${d}, ${h}`
            }
            if (graph.interval === "minute" && period !== "realtime") {
              return formatHour(label, tz)
            }

            switch (graph.interval) {
              case "minute":
              case "hour":
                return formatHour(label, tz)
              case "day":
              case "week":
                return formatDay(label, shouldShowYear, tz)
              case "month":
                return formatMonth(label, tz)
              default:
                return formatDay(label, shouldShowYear, tz)
            }
          },
        },
        grid: {
          display: false,
        },
      },
    },
  }
}

type TopStatsGridProps = {
  stats: TopStat[]
  graphableMetrics: string[]
  selectedMetric: string
  onSelectMetric: (metric: string) => void
  comparingFrom?: string | null
  comparingTo?: string | null
  period?: string
  timezone?: string
  showComparison?: boolean
  primaryFrom?: string
  primaryTo?: string
}

function TopStatsGrid({
  stats,
  graphableMetrics,
  selectedMetric,
  onSelectMetric,
  comparingFrom,
  comparingTo,
  period = "day",
  timezone = dayjs.tz.guess(),
  showComparison = false,
  primaryFrom,
  primaryTo,
}: TopStatsGridProps) {
  const selectable = new Set(graphableMetrics)

  // Filter out "Live visitors" - it's shown in the top bar, not as a graphable metric
  const displayStats = stats.filter(
    (stat) => stat.graphMetric !== "currentVisitors"
  )

  const items = displayStats.map((stat) => {
    const canSelect = stat.graphMetric && selectable.has(stat.graphMetric)
    const isSelected = canSelect && stat.graphMetric === selectedMetric
    const classes = [
      "group flex min-w-[100px] flex-1 flex-col gap-0.5 px-3 py-2 text-left transition rounded-lg",
      canSelect
        ? "hover:bg-accent focus:bg-accent focus:outline-hidden"
        : "cursor-default",
      isSelected
        ? "border border-dashed border-border bg-accent/50"
        : "border border-transparent",
    ]
      .filter(Boolean)
      .join(" ")

    // Primary period label (always shown like Plausible)
    const primaryLabel = formatPrimaryRangeLabel(
      period,
      primaryFrom,
      primaryTo,
      timezone
    )

    // Optional comparison value + range label (rendered as two lines like Plausible)
    const hasComparison =
      showComparison &&
      typeof stat.comparisonValue === "number" &&
      !Number.isNaN(stat.comparisonValue)
    let comparisonValue: string | null = null
    let comparisonLabel: string | null = null
    if (hasComparison) {
      const comp: TopStat = { ...stat, value: stat.comparisonValue as number }
      comparisonValue = formatTopStatValue(comp)
      comparisonLabel = formatComparisonRangeLabel(
        comparingFrom,
        comparingTo,
        period,
        timezone
      )
    }

    return (
      <button
        key={stat.name}
        type="button"
        className={classes}
        onClick={() => {
          if (canSelect && stat.graphMetric) {
            onSelectMetric(stat.graphMetric)
          }
        }}
        disabled={!canSelect}
      >
        <span
          className={[
            "text-xs",
            isSelected
              ? "font-medium text-primary"
              : "text-muted-foreground group-hover:text-foreground",
          ].join(" ")}
        >
          {stat.name}
        </span>
        <span className="text-lg font-bold tabular-nums">
          {formatTopStatValue(stat)}
        </span>
        {primaryLabel && showComparison ? (
          <span className="text-xs text-muted-foreground">{primaryLabel}</span>
        ) : null}
        {comparisonValue ? (
          <>
            <span className="text-lg font-bold text-muted-foreground tabular-nums">
              {comparisonValue}
            </span>
            {comparisonLabel ? (
              <span className="text-xs text-muted-foreground">
                {comparisonLabel}
              </span>
            ) : null}
          </>
        ) : null}
        {(() => {
          if (showComparison || stat.change == null) return null

          const direction = topStatChangeDirection(stat.change)
          const tone = topStatChangeTone(stat.graphMetric, stat.change)

          return (
            <span
              className={`inline-flex items-center gap-1 text-xs font-medium ${
                tone === "good"
                  ? "text-emerald-600 dark:text-emerald-400"
                  : "text-rose-600 dark:text-rose-400"
              }`}
            >
              {direction === "up" ? "▲ " : direction === "down" ? "▼ " : ""}
              {formatTopStatChangeValue(stat.change)}
            </span>
          )
        })()}
      </button>
    )
  })

  return (
    <div className="grid grid-cols-2 gap-1 border-b border-border pb-3 sm:grid-cols-3 lg:flex lg:flex-wrap">
      {items}
    </div>
  )
}

// Plausible's exact formatting logic
function numberShortFormatter(num: number): string {
  const THOUSAND = 1000
  const HUNDRED_THOUSAND = 100000
  const MILLION = 1000000
  const HUNDRED_MILLION = 100000000
  const BILLION = 1000000000
  const HUNDRED_BILLION = 100000000000

  if (num >= THOUSAND && num < MILLION) {
    const thousands = num / THOUSAND
    if (thousands === Math.floor(thousands) || num >= HUNDRED_THOUSAND) {
      return Math.floor(thousands) + "k"
    } else {
      return Math.floor(thousands * 10) / 10 + "k"
    }
  } else if (num >= MILLION && num < BILLION) {
    const millions = num / MILLION
    if (millions === Math.floor(millions) || num >= HUNDRED_MILLION) {
      return Math.floor(millions) + "M"
    } else {
      return Math.floor(millions * 10) / 10 + "M"
    }
  } else if (num >= BILLION) {
    const billions = num / BILLION
    if (billions === Math.floor(billions) || num >= HUNDRED_BILLION) {
      return Math.floor(billions) + "B"
    } else {
      return Math.floor(billions * 10) / 10 + "B"
    }
  } else {
    return num.toString()
  }
}

function durationFormatter(duration: number): string {
  const hours = Math.floor(duration / 60 / 60)
  const minutes = Math.floor(duration / 60) % 60
  const seconds = Math.floor(duration - minutes * 60 - hours * 60 * 60)

  if (hours > 0) {
    return `${hours}h ${minutes}m ${seconds}s`
  } else if (minutes > 0) {
    const paddedSeconds = seconds.toString().padStart(2, "0")
    return `${minutes}m ${paddedSeconds}s`
  } else {
    return `${seconds}s`
  }
}

function formatTopStatValue(stat: TopStat) {
  const value = Number(stat.value ?? 0)

  // Prefer explicit metric key when present for stable formatting
  const metric = (stat.graphMetric || "").toString().toLowerCase()
  switch (metric) {
    case "bounce_rate":
    case "conversion_rate":
    case "scroll_depth":
      return `${value.toFixed(2)}%`
    case "time_on_page":
    case "visit_duration":
      return durationFormatter(value)
    case "views_per_visit":
      return value.toFixed(2)
    case "visitors":
    case "events":
    case "visits":
    case "pageviews":
      return numberShortFormatter(value)
    default: {
      // Fallback to name heuristics (covers rare tiles without graphMetric)
      const name = (stat.name || "").toLowerCase()
      if (name.includes("rate") || name.includes("scroll"))
        return `${value.toFixed(2)}%`
      if (name.includes("duration") || name.includes("time on"))
        return durationFormatter(value)
      if (name.includes("views per")) return value.toFixed(2)
      return numberShortFormatter(value)
    }
  }
}

// Format the comparison period label to mirror Plausible cards
function formatComparisonRangeLabel(
  fromISO?: string | null,
  toISO?: string | null,
  period = "day",
  tz = dayjs.tz.guess()
) {
  if (!fromISO && !toISO) return ""
  const from = fromISO ? dayjs.utc(fromISO).tz(tz) : null
  const to = toISO ? dayjs.utc(toISO).tz(tz) : null

  // Helper formatters
  const fmtDay = (d: dayjs.Dayjs) => d.format("ddd, D MMM YYYY")
  const fmtMonth = (d: dayjs.Dayjs) => d.format("MMM YYYY")

  // Prefer concise single-labels when the comparison covers a whole day/month/year
  if (period === "day" && from) return fmtDay(from)

  if (period === "month" && from && to) {
    const isFullMonth = from.date() === 1 && to.endOf("month").isSame(to)
    if (isFullMonth) return fmtMonth(from)
  }

  if (period === "year" && from && to) {
    const isFullYear =
      from.month() === 0 &&
      from.date() === 1 &&
      to.month() === 11 &&
      to.date() === 31
    if (isFullYear) return from.format("YYYY")
  }

  // Generic fallback: compact range
  if (from && to)
    return `${from.format("D MMM YYYY")} – ${to.format("D MMM YYYY")}`
  if (from) return fmtDay(from)
  if (to) return fmtDay(to)
  return ""
}

function formatPrimaryRangeLabel(
  period?: string,
  fromISO?: string | null,
  toISO?: string | null,
  tz = dayjs.tz.guess()
) {
  if (!period) return ""
  if (fromISO) {
    const from = dayjs.utc(fromISO).tz(tz)
    const to = toISO ? dayjs.utc(toISO).tz(tz) : null
    switch (period) {
      case "day":
        return from.format("ddd, D MMM")
      case "month":
        return from.format("MMM YYYY")
      case "year":
        return from.format("YYYY")
      default:
        if (to)
          return `${from.format("D MMM YYYY")} – ${to.format("D MMM YYYY")}`
        return from.format("D MMM YYYY")
    }
  }
  return ""
}

type IntervalPickerProps = {
  interval: string
  onChange: (interval: string) => void
}

function IntervalPicker({ interval, onChange }: IntervalPickerProps) {
  // Determine allowed options similar to Plausible
  const { query } = useQueryContext()
  const options = availableIntervalsForPeriod(query.period)

  const currentLabel = INTERVAL_LABELS[interval] || interval

  return (
    <DropdownMenu>
      <DropdownMenuTrigger className="inline-flex h-7 items-center gap-1 text-sm font-medium text-primary underline-offset-4 hover:underline">
        {currentLabel}
        <ChevronDown className="ml-1 size-4" />
      </DropdownMenuTrigger>
      <DropdownMenuContent align="end">
        {options.map((opt) => (
          <DropdownMenuItem
            key={opt}
            onClick={() => onChange(opt)}
            data-selected={opt === interval}
          >
            <span className={opt === interval ? "font-semibold" : ""}>
              {INTERVAL_LABELS[opt]}
            </span>
          </DropdownMenuItem>
        ))}
      </DropdownMenuContent>
    </DropdownMenu>
  )
}
