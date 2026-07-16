import type { AnalyticsQuery } from "../types"
import { buildQueryNavigationPath } from "./query-navigation"

export type LocationFilterDimension = "country" | "region" | "city"

export function buildLocationDrilldownPath({
  query,
  search,
  reportsPath,
  dimension,
  value,
  label,
}: {
  query: AnalyticsQuery
  search: string
  reportsPath: string
  dimension: LocationFilterDimension
  value: string
  label?: string
}) {
  const labels = { ...(query.labels || {}) }

  if (label && label !== value) {
    labels[dimension] = label
  } else {
    delete labels[dimension]
  }

  const nextQuery: AnalyticsQuery = {
    ...query,
    filters: { ...query.filters, [dimension]: value },
    labels,
  }
  return buildQueryNavigationPath({
    query: nextQuery,
    search,
    pathname: reportsPath,
    reportsPath,
    closeDialog: true,
  })
}
