import type { ListItem, ListMetricKey } from "../types"
import { normalizeMetricKey } from "./metric-key"
import {
  durationFormatter,
  fractionPercentageFormatter,
  nullable,
  numberLongFormatter,
  numberShortFormatter,
  percentageFormatter,
} from "./number-formatter"

export type MetricLabelMap =
  | Partial<Record<ListMetricKey, string>>
  | Record<string, string>
  | undefined

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

const LONG_FORMATTERS: Partial<
  Record<ListMetricKey, (value: number | null | undefined) => string>
> = {
  visitors: nullable(numberLongFormatter),
  clicks: nullable(numberLongFormatter),
  events: nullable(numberLongFormatter),
  visits: nullable(numberLongFormatter),
  uniques: nullable(numberLongFormatter),
  total: nullable(numberLongFormatter),
  pageviews: nullable(numberLongFormatter),
  impressions: nullable(numberLongFormatter),
  percentage: (value) => fractionPercentageFormatter(value ?? null),
  conversionRate: (value) => percentageFormatter(value ?? null),
  exitRate: (value) => percentageFormatter(value ?? null),
  bounceRate: (value) => percentageFormatter(value ?? null),
  visitDuration: nullable(durationFormatter),
  scrollDepth: (value) => percentageFormatter(value ?? null),
  timeOnPage: nullable(durationFormatter),
  ctr: (value) => percentageFormatter(value ?? null),
  position: (value) => {
    if (value == null || Number.isNaN(value as number)) return "-"
    return (Math.round((value as number) * 10) / 10).toFixed(1)
  },
}

export function resolveMetricLabel(
  metric: string,
  metricLabels?: MetricLabelMap,
  options?: { compactPercentage?: boolean }
) {
  const normalizedMetric = normalizeMetricKey(metric)

  if (options?.compactPercentage && normalizedMetric === "percentage") {
    return "%"
  }

  const labelMap = metricLabels as Record<string, string> | undefined

  return (
    labelMap?.[metric] ??
    labelMap?.[normalizedMetric] ??
    METRIC_LABELS[normalizedMetric] ??
    metric
  )
}

export function formatMetric(metric: string, value: ListItem[keyof ListItem]) {
  const formatter = FORMATTERS[normalizeMetricKey(metric)]
  if (formatter) {
    return formatter(typeof value === "number" ? value : Number(value))
  }
  return value == null ? "—" : String(value)
}

export function formatMetricLong(
  metric: string,
  value: ListItem[keyof ListItem]
) {
  const formatter = LONG_FORMATTERS[normalizeMetricKey(metric)]
  if (formatter) {
    return formatter(typeof value === "number" ? value : Number(value))
  }
  return value == null ? "—" : String(value)
}

export function isMetricAbbreviated(
  metric: string,
  value: ListItem[keyof ListItem]
) {
  return (
    value != null &&
    value !== "" &&
    formatMetric(metric, value) !== formatMetricLong(metric, value)
  )
}

export function metricLabelSuffix(
  metric: string,
  metricLabels?: MetricLabelMap
) {
  const label = resolveMetricLabel(metric, metricLabels)
  return label.length < 3 ? "" : ` ${label.toLowerCase()}`
}
