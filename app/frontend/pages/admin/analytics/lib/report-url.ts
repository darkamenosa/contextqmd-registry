import { canonicalizeDashboardSearchParams } from "./dashboard-url-state"

export function canonicalReportSearch(
  input: URLSearchParams | string | undefined
) {
  return canonicalizeDashboardSearchParams(input ?? "").toString()
}

export function buildReportUrl(
  pathname: string,
  search: URLSearchParams | string | undefined
) {
  const queryString = canonicalReportSearch(search)
  return queryString ? `${pathname}?${queryString}` : pathname
}
