import type { ListMetricKey } from "../types"

export function pickCardMetrics(metrics: ListMetricKey[]): ListMetricKey[] {
  const preferred: ListMetricKey[] = []

  if (metrics.includes("visitors")) preferred.push("visitors")
  if (metrics.includes("percentage")) preferred.push("percentage")
  else if (metrics.includes("conversionRate")) preferred.push("conversionRate")

  return preferred.length > 0 ? preferred : metrics.slice(0, 2)
}
