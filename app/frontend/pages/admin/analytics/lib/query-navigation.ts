import type { AnalyticsQuery } from "../types"
import { baseAnalyticsPath } from "./dialog-path"
import { mergeReportQueryParams } from "./query-codec"
import { buildReportUrl } from "./report-url"

export function buildQueryNavigationPath({
  query,
  search,
  pathname,
  reportsPath,
  closeDialog = false,
}: {
  query: AnalyticsQuery
  search: string
  pathname: string
  reportsPath: string
  closeDialog?: boolean
}) {
  const nextSearch = mergeReportQueryParams(search, query)

  if (closeDialog) {
    return baseAnalyticsPath(nextSearch.toString(), reportsPath)
  }

  return buildReportUrl(pathname, nextSearch)
}
