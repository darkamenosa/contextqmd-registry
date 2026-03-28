const STORAGE_PREFIX = "admin.analytics"

function preferenceKey(siteDomain: string, key: "metric" | "interval") {
  return `${STORAGE_PREFIX}.${siteDomain}.${key}`
}

export function availableIntervalsForPeriod(period: string) {
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

export function resolveInitialMetricSelection(
  graphableMetrics: string[],
  fallbackMetric: string,
  requestedMetric?: string | null
) {
  if (requestedMetric && graphableMetrics.includes(requestedMetric)) {
    return requestedMetric
  }
  return fallbackMetric
}

export function resolveInitialIntervalSelection(
  period: string,
  fallbackInterval: string,
  requestedInterval?: string | null
) {
  const options = availableIntervalsForPeriod(period)
  if (requestedInterval && options.includes(requestedInterval)) {
    return requestedInterval
  }
  if (options.includes(fallbackInterval)) {
    return fallbackInterval
  }
  return options[0] ?? fallbackInterval
}

export function resolvePreferredMetric(
  graphableMetrics: string[],
  siteDomain: string,
  fallbackMetric: string,
  requestedMetric?: string | null
) {
  if (requestedMetric && graphableMetrics.includes(requestedMetric)) {
    return requestedMetric
  }
  if (typeof window === "undefined") return fallbackMetric
  const stored = localStorage.getItem(preferenceKey(siteDomain, "metric"))
  if (stored && graphableMetrics.includes(stored)) {
    return stored
  }
  return fallbackMetric
}

export function resolvePreferredInterval(
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
    const stored = localStorage.getItem(preferenceKey(siteDomain, "interval"))
    if (stored && options.includes(stored)) {
      return stored
    }
  }
  if (options.includes(fallbackInterval)) {
    return fallbackInterval
  }
  return options[0] ?? fallbackInterval
}

export function writePreferredMetric(siteDomain: string, metric: string) {
  localStorage.setItem(preferenceKey(siteDomain, "metric"), metric)
}

export function writePreferredInterval(siteDomain: string, interval: string) {
  localStorage.setItem(preferenceKey(siteDomain, "interval"), interval)
}
