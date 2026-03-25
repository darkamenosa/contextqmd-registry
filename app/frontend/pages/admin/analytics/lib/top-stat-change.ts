const INVERTED_TREND_METRICS = new Set(["bounce_rate", "exit_rate"])

function normalizeMetric(metric?: string | null) {
  return (metric || "").toLowerCase()
}

export function formatTopStatChangeValue(change: number): string {
  const value = Math.abs(change)

  if (value > 0 && value < 0.1) {
    return `${value.toFixed(2)}%`
  }

  return `${value.toFixed(1).replace(/\.0$/, "")}%`
}

export function topStatChangeTone(metric: string | undefined, change: number) {
  const inverted = INVERTED_TREND_METRICS.has(normalizeMetric(metric))
  return change > 0 !== inverted ? "good" : "bad"
}

export function topStatChangeDirection(change: number) {
  if (change > 0) return "up"
  if (change < 0) return "down"
  return "flat"
}
