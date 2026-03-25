import type { ListMetricKey } from "../types"

export function normalizeMetricKey(metric: string): ListMetricKey {
  return metric.replace(/_([a-z])/g, (_, c: string) =>
    c.toUpperCase()
  ) as ListMetricKey
}
