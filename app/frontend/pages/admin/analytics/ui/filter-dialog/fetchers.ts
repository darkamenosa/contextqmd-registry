import { useCallback } from "react"

import { fetchListPage } from "../../api"
import { useAnalyticsApi } from "../../hooks/use-analytics-api"
import { useAnalyticsHost } from "../../host-context"
import { useQueryContext } from "../../query-context"
import type { AnalyticsQuery, ListPayload } from "../../types"
import type { SuggestionOption } from "./shared"

function listResultsToOptions(
  payload: ListPayload,
  valueSelector?: (item: ListPayload["results"][number]) => string
): SuggestionOption[] {
  return payload.results.map((item) => ({
    label: String(item.name),
    value: valueSelector ? valueSelector(item) : String(item.name),
  }))
}

export function usePageFetcher(mode: "default" | "entry" | "exit") {
  const host = useAnalyticsHost()
  const { query } = useQueryContext()
  return useCallback(
    async (input: string) => {
      const extras: Record<string, string> = {}
      if (mode === "entry") extras.mode = "entry"
      if (mode === "exit") extras.mode = "exit"

      try {
        const payload: ListPayload = await fetchListPage(
          host.scopedPath("/pages"),
          query as AnalyticsQuery,
          extras,
          { limit: 20, page: 1, search: input }
        )
        return listResultsToOptions(payload)
      } catch {
        return []
      }
    },
    [host, mode, query]
  )
}

export function useLocationFetcher(mode: "countries" | "regions" | "cities") {
  const host = useAnalyticsHost()
  const { query } = useQueryContext()
  return useCallback(
    async (input: string) => {
      try {
        const payload: ListPayload = await fetchListPage(
          host.scopedPath("/locations"),
          query as AnalyticsQuery,
          { mode },
          { limit: 20, page: 1, search: input }
        )
        return listResultsToOptions(payload, (item) =>
          String(item.code ?? item.name)
        )
      } catch {
        return []
      }
    },
    [host, mode, query]
  )
}

export function useSourcesFetcher(
  mode:
    | "all"
    | "utm-source"
    | "utm-medium"
    | "utm-campaign"
    | "utm-content"
    | "utm-term"
) {
  const host = useAnalyticsHost()
  const { query } = useQueryContext()
  return useCallback(
    async (input: string) => {
      try {
        const payload: ListPayload = await fetchListPage(
          host.scopedPath("/sources"),
          query as AnalyticsQuery,
          { mode },
          { limit: 20, page: 1, search: input }
        )
        return listResultsToOptions(payload)
      } catch {
        return []
      }
    },
    [host, mode, query]
  )
}

export function useDeviceFetcher(
  mode:
    | "browsers"
    | "browser-versions"
    | "operating-systems"
    | "operating-system-versions"
    | "screen-sizes"
) {
  const host = useAnalyticsHost()
  const { query } = useQueryContext()
  return useCallback(
    async (input: string) => {
      try {
        const payload: ListPayload = await fetchListPage(
          host.scopedPath("/devices"),
          query as AnalyticsQuery,
          { mode },
          { limit: 20, page: 1, search: input }
        )
        return listResultsToOptions(payload)
      } catch {
        return []
      }
    },
    [host, mode, query]
  )
}

export function useBehaviorFetcher(mode: "conversions") {
  const host = useAnalyticsHost()
  const { query } = useQueryContext()
  return useCallback(
    async (input: string) => {
      try {
        const payload: ListPayload = await fetchListPage(
          host.scopedPath("/behaviors"),
          query as AnalyticsQuery,
          { mode },
          { limit: 20, page: 1, search: input }
        )
        return listResultsToOptions(payload)
      } catch {
        return []
      }
    },
    [host, mode, query]
  )
}

export function useBehaviorPropertyKeyFetcher() {
  const { fetchBehaviorPropertyKeys } = useAnalyticsApi()
  const { query } = useQueryContext()
  return useCallback(
    async (input: string) => {
      try {
        const keys = await fetchBehaviorPropertyKeys(query as AnalyticsQuery)
        const needle = input.trim().toLowerCase()
        return keys
          .filter((key) => (needle ? key.toLowerCase().includes(needle) : true))
          .map((key) => ({ label: key, value: key }))
      } catch {
        return []
      }
    },
    [fetchBehaviorPropertyKeys, query]
  )
}

export function useBehaviorPropertyValueFetcher(property: string) {
  const { fetchBehaviorPropertyValues } = useAnalyticsApi()
  const { query } = useQueryContext()
  return useCallback(
    async (input: string) => {
      const propertyName = property.trim()
      if (!propertyName) return []

      try {
        return await fetchBehaviorPropertyValues(
          query as AnalyticsQuery,
          propertyName,
          input
        )
      } catch {
        return []
      }
    },
    [fetchBehaviorPropertyValues, property, query]
  )
}
