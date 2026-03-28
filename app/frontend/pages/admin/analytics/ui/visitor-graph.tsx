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
import {
  createChartData,
  createChartOptions,
  formatComparisonRangeLabel,
  formatPrimaryRangeLabel,
  formatTopStatValue,
} from "./visitor-graph/chart-utils"
import {
  availableIntervalsForPeriod,
  resolvePreferredInterval,
  resolvePreferredMetric,
  writePreferredInterval,
  writePreferredMetric,
} from "./visitor-graph/preferences"

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
  const graphRequestIdRef = useRef(0)
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
    const requestId = graphRequestIdRef.current + 1
    graphRequestIdRef.current = requestId
    abortRef.current?.abort()
    abortRef.current = controller
    startTransition(() => setLoading(true))

    fetchGraphData(effectiveMetric, effectiveInterval, controller)
      .then((data) => {
        if (graphRequestIdRef.current !== requestId) return
        setGraph(data)
      })
      .catch((error) => {
        if (error.name !== "AbortError") {
          console.error(error)
        }
      })
      .finally(() => {
        if (graphRequestIdRef.current !== requestId) return
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
      writePreferredMetric(site.domain, next)
      setSelectedMetric(next)
    },
    [effectiveMetric, site.domain]
  )

  const changeInterval = useCallback(
    (nextInterval: string) => {
      if (nextInterval === effectiveInterval) return
      writePreferredInterval(site.domain, nextInterval)
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
