import { type ChartDataset, type ChartOptions } from "chart.js"
import dayjs from "dayjs"
import timezone from "dayjs/plugin/timezone"
import utc from "dayjs/plugin/utc"

import type { MainGraphPayload, TopStat } from "../../types"

dayjs.extend(utc)
dayjs.extend(timezone)

type ChartPoint = number | null

function is12HourClock(): boolean {
  if (typeof navigator === "undefined") return false
  const browserFormat = new Intl.DateTimeFormat(navigator.language, {
    hour: "numeric",
  })
  return browserFormat.resolvedOptions().hour12 ?? false
}

function formatHour(isoDate: string, tz: string): string {
  const date = dayjs.utc(isoDate).tz(tz)
  return is12HourClock() ? date.format("ha") : date.format("HH:mm")
}

function formatDay(isoDate: string, includeYear: boolean, tz: string): string {
  const date = dayjs.utc(isoDate).tz(tz)
  return includeYear ? date.format("D MMM YY") : date.format("D MMM")
}

function formatMonth(isoDate: string, tz: string): string {
  return dayjs.utc(isoDate).tz(tz).format("MMMM YYYY")
}

function hasMultipleYears(labels: string[]): boolean {
  const years = labels
    .filter((label) => typeof label === "string")
    .map((label) => label.split("-")[0])
  return new Set(years).size > 1
}

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

export function numberShortFormatter(num: number): string {
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
    }
    return Math.floor(thousands * 10) / 10 + "k"
  }

  if (num >= MILLION && num < BILLION) {
    const millions = num / MILLION
    if (millions === Math.floor(millions) || num >= HUNDRED_MILLION) {
      return Math.floor(millions) + "M"
    }
    return Math.floor(millions * 10) / 10 + "M"
  }

  if (num >= BILLION) {
    const billions = num / BILLION
    if (billions === Math.floor(billions) || num >= HUNDRED_BILLION) {
      return Math.floor(billions) + "B"
    }
    return Math.floor(billions * 10) / 10 + "B"
  }

  return num.toString()
}

export function durationFormatter(duration: number): string {
  const hours = Math.floor(duration / 60 / 60)
  const minutes = Math.floor(duration / 60) % 60
  const seconds = Math.floor(duration - minutes * 60 - hours * 60 * 60)

  if (hours > 0) return `${hours}h ${minutes}m ${seconds}s`
  if (minutes > 0) {
    return `${minutes}m ${seconds.toString().padStart(2, "0")}s`
  }
  return `${seconds}s`
}

export function formatTopStatValue(stat: TopStat) {
  const value = Number(stat.value ?? 0)
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
      const name = (stat.name || "").toLowerCase()
      if (name.includes("rate") || name.includes("scroll")) {
        return `${value.toFixed(2)}%`
      }
      if (name.includes("duration") || name.includes("time on")) {
        return durationFormatter(value)
      }
      if (name.includes("views per")) return value.toFixed(2)
      return numberShortFormatter(value)
    }
  }
}

export function formatComparisonRangeLabel(
  fromISO?: string | null,
  toISO?: string | null,
  period = "day",
  tz = dayjs.tz.guess()
) {
  if (!fromISO && !toISO) return ""
  const from = fromISO ? dayjs.utc(fromISO).tz(tz) : null
  const to = toISO ? dayjs.utc(toISO).tz(tz) : null
  const fmtDay = (date: dayjs.Dayjs) => date.format("ddd, D MMM YYYY")
  const fmtMonth = (date: dayjs.Dayjs) => date.format("MMM YYYY")

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

  if (from && to)
    return `${from.format("D MMM YYYY")} – ${to.format("D MMM YYYY")}`
  if (from) return fmtDay(from)
  if (to) return fmtDay(to)
  return ""
}

export function formatPrimaryRangeLabel(
  period?: string,
  fromISO?: string | null,
  toISO?: string | null,
  tz = dayjs.tz.guess()
) {
  if (!period) return ""
  if (!fromISO) return ""

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
      if (to) return `${from.format("D MMM YYYY")} – ${to.format("D MMM YYYY")}`
      return from.format("D MMM YYYY")
  }
}

export function createChartData(graph: MainGraphPayload) {
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
      tension: 0,
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
      yAxisID: "y",
    })
  }

  return {
    labels: graph.labels,
    datasets,
  }
}

export function createChartOptions(
  graph: MainGraphPayload,
  period: string,
  tz: string
): ChartOptions<"line"> {
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

  const metricFormatter = (value: number): string => {
    const metric = graph.metric
    if (metric === "visit_duration" || metric === "time_on_page") {
      return durationFormatter(value)
    }
    if (
      metric === "bounce_rate" ||
      metric === "conversion_rate" ||
      metric === "scroll_depth"
    ) {
      return `${value.toFixed(2)}%`
    }
    if (metric === "views_per_visit") return value.toFixed(2)
    return numberShortFormatter(value)
  }

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const externalTooltip = (ctx: any) => {
    const { chart, tooltip } = ctx
    let element = chart.canvas.parentNode?.querySelector(
      ".analytics-tooltip"
    ) as HTMLDivElement | null
    if (!element) {
      element = document.createElement("div")
      element.className = "analytics-tooltip"
      element.style.position = "absolute"
      element.style.pointerEvents = "none"
      element.style.backgroundColor = "var(--popover)"
      element.style.border = "1px solid var(--border)"
      element.style.borderRadius = "10px"
      element.style.padding = "10px 12px"
      element.style.color = "var(--popover-foreground)"
      element.style.zIndex = "60"
      element.style.minWidth = "220px"
      element.style.boxShadow = "0 4px 12px oklch(0 0 0 / 0.1)"
      chart.canvas.parentNode?.appendChild(element)
    }

    if (!element) return
    if (tooltip.opacity === 0) {
      element.style.opacity = "0"
      return
    }

    const idx = tooltip.dataPoints?.[0]?.dataIndex ?? 0
    const labelISO = graph.labels[idx]
    const comparisonISO = graph.comparisonLabels?.[idx]
    const shouldShowYear = hasMultipleYears(graph.labels)
    const baseTitle = METRIC_LABELS[graph.metric] || graph.metric

    const formattedPrimary = (() => {
      if (!labelISO) return ""
      if (graph.interval === "hour") {
        return `${formatDay(labelISO, shouldShowYear, tz)}, ${formatHour(labelISO, tz)}`
      }
      if (graph.interval === "minute") return formatHour(labelISO, tz)
      if (graph.interval === "month") return formatMonth(labelISO, tz)
      return formatDay(labelISO, shouldShowYear, tz)
    })()

    const formattedComparison = (() => {
      if (!comparisonISO) return null
      if (graph.interval === "hour") {
        return `${formatDay(comparisonISO, hasMultipleYears(graph.comparisonLabels || []), tz)}, ${formatHour(comparisonISO, tz)}`
      }
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

    const datasets = (chart.config.data.datasets || []) as Array<{
      label?: string
      borderColor?: unknown
    }>
    const primaryDataset =
      datasets.find((dataset) => dataset.label !== "Comparison") ?? datasets[0]
    const comparisonDataset = datasets.find(
      (dataset) => dataset.label === "Comparison"
    )
    const primaryColor =
      (primaryDataset?.borderColor as string) || "rgba(26, 26, 26, 1)"
    const comparisonColor =
      (comparisonDataset?.borderColor as string) || "rgba(128, 128, 128, 0.75)"

    const primaryValStr = metricFormatter(currentVal)
    const comparisonValStr =
      comparisonVal == null ? null : metricFormatter(comparisonVal)

    element.innerHTML = `
      <div style="display:flex;align-items:center;gap:12px;margin-bottom:6px;">
        <div style="font-weight:800;font-size:16px;line-height:1.2;color:var(--foreground);">${baseTitle}</div>
        ${changePct == null ? "" : `<div style="margin-left:auto;font-weight:600;color:${changeColor};">${changeStr}</div>`}
      </div>
      <div style="display:grid;grid-template-columns:auto 1fr auto;gap:6px 10px;align-items:center;">
        <span style="width:10px;height:10px;border-radius:50%;background:${primaryColor};display:inline-block"></span>
        <div style="color:var(--muted-foreground);font-size:13px;">${formattedPrimary}</div>
        <div style="font-weight:800;font-size:16px;color:var(--foreground);">${primaryValStr}</div>
        ${
          comparisonValStr != null
            ? `
          <span style="width:10px;height:10px;border-radius:50%;background:${comparisonColor};display:inline-block;opacity:0.7"></span>
          <div style="color:var(--muted-foreground);font-size:13px;">${formattedComparison}</div>
          <div style="font-weight:800;font-size:16px;color:var(--foreground);opacity:0.85;">${comparisonValStr}</div>
        `
            : ""
        }
      </div>
    `

    const parent = chart.canvas.parentNode as HTMLElement
    const { offsetLeft, offsetTop } = chart.canvas
    element.style.opacity = "1"

    let left = offsetLeft + tooltip.caretX
    let top = offsetTop + tooltip.caretY

    const minX = 6
    const maxX = parent.clientWidth - element.offsetWidth - 6
    const minY = 6
    const maxY = parent.clientHeight - element.offsetHeight - 6
    if (left < minX) left = minX
    if (left > maxX) left = maxX
    if (top < minY) top = minY
    if (top > maxY) top = maxY
    element.style.left = `${left}px`
    element.style.top = `${top}px`
  }

  return {
    responsive: true,
    maintainAspectRatio: false,
    onHover: (_event, _activeElements, chart) => {
      chart.canvas.style.cursor = "pointer"
    },
    interaction: {
      mode: "index",
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
          callback(value) {
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
          callback(value) {
            const scale = this as {
              getLabelForValue: (value: number | string) => string
            }
            const label = scale.getLabelForValue(value)
            if (!label || label === "__blank__") return ""

            const shouldShowYear = hasMultipleYears(graph.labels)

            if (graph.interval === "hour" && period !== "day") {
              return `${formatDay(label, shouldShowYear, tz)}, ${formatHour(label, tz)}`
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
