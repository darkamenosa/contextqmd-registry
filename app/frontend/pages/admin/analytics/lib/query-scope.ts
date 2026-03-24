import { useMemo, useRef } from "react"

import { buildQueryParams } from "../api"
import type { AnalyticsQuery } from "../types"

type ScopedQueryOptions = {
  omitMode?: boolean
  omitMetric?: boolean
  omitInterval?: boolean
}

export function stripQueryFields(
  query: AnalyticsQuery,
  options: ScopedQueryOptions = {}
): AnalyticsQuery {
  const next = { ...query }

  if (options.omitMode) delete next.mode
  if (options.omitMetric) delete next.metric
  if (options.omitInterval) delete next.interval

  return next
}

export function buildScopedQueryKey(
  query: AnalyticsQuery,
  options: ScopedQueryOptions = {}
): string {
  return buildQueryParams(stripQueryFields(query, options))
}

export function useScopedQuery(
  query: AnalyticsQuery,
  options: ScopedQueryOptions = {}
) {
  const { omitInterval = false, omitMetric = false, omitMode = false } = options
  const key = useMemo(
    () => buildScopedQueryKey(query, { omitInterval, omitMetric, omitMode }),
    [omitInterval, omitMetric, omitMode, query]
  )
  const valueRef = useRef<{ key: string; value: AnalyticsQuery } | null>(null)

  if (!valueRef.current || valueRef.current.key !== key) {
    valueRef.current = {
      key,
      value: stripQueryFields(query, { omitInterval, omitMetric, omitMode }),
    }
  }

  return valueRef.current
}
