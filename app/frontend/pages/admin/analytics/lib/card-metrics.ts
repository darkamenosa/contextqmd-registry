import type { ListMetricKey, ListPayload } from "../types"

export function pickCardMetrics(metrics: ListMetricKey[]): ListMetricKey[] {
  const preferred: ListMetricKey[] = []

  if (metrics.includes("visitors")) preferred.push("visitors")
  if (metrics.includes("percentage")) preferred.push("percentage")
  else if (metrics.includes("conversionRate")) preferred.push("conversionRate")

  return preferred.length > 0 ? preferred : metrics.slice(0, 2)
}

type LimitListPayloadOptions = {
  limit?: number
  metricKey?: ListMetricKey
  metrics?: ListMetricKey[]
}

export function limitListPayloadForCard(
  payload: ListPayload,
  options: LimitListPayloadOptions = {}
): ListPayload {
  const {
    limit = 9,
    metricKey = payload.metrics[0] ?? "visitors",
    metrics = payload.metrics,
  } = options

  const results = [...payload.results].sort((a, b) => {
    const av = Number(a[metricKey] ?? 0)
    const bv = Number(b[metricKey] ?? 0)
    if (av === bv) return String(a.name).localeCompare(String(b.name))
    return bv - av
  })

  return {
    ...payload,
    metrics,
    results: results.slice(0, limit),
    meta: { ...payload.meta, hasMore: payload.results.length > limit },
  }
}
