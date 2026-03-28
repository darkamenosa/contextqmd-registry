import type { AnalyticsQuery } from "../types"
import { canonicalizeDashboardSearchParams } from "./dashboard-url-state"

const NOT_URL_ENCODED_CHARACTERS = ":/"

function encodeURIComponentPermissive(
  input: string,
  permittedCharacters: string
): string {
  let result = encodeURIComponent(input)
  for (const ch of permittedCharacters) {
    const encoded = encodeURIComponent(ch)
    if (encoded !== ch) {
      result = result.split(encoded).join(ch)
    }
  }
  return result
}

function serializeFilterEntry(operator: string, key: string, value: string) {
  const op = encodeURIComponentPermissive(operator, NOT_URL_ENCODED_CHARACTERS)
  const dim = encodeURIComponentPermissive(key, NOT_URL_ENCODED_CHARACTERS)
  const clause = encodeURIComponentPermissive(value, NOT_URL_ENCODED_CHARACTERS)
  return `f=${op},${dim},${clause}`
}

function serializeLabelEntry(key: string, label: string) {
  const encodedKey = encodeURIComponentPermissive(
    key,
    NOT_URL_ENCODED_CHARACTERS
  )
  const encodedValue = encodeURIComponentPermissive(
    label,
    NOT_URL_ENCODED_CHARACTERS
  )
  return `l=${encodedKey},${encodedValue}`
}

function parseTokenWithRemainder(
  token: string,
  delimiter: string,
  expectedParts: number
): string[] | null {
  const first = token.indexOf(delimiter)
  if (first < 0) return null

  if (expectedParts === 2) {
    return [token.slice(0, first), token.slice(first + delimiter.length)]
  }

  const second = token.indexOf(delimiter, first + delimiter.length)
  if (second < 0) return null

  return [
    token.slice(0, first),
    token.slice(first + delimiter.length, second),
    token.slice(second + delimiter.length),
  ]
}

const REPORT_QUERY_PARAM_KEYS = [
  "period",
  "comparison",
  "with_imported",
  "date",
  "from",
  "to",
  "compare_from",
  "compare_to",
  "match_day_of_week",
] as const

export function sanitizeReportQuery(query: AnalyticsQuery): AnalyticsQuery {
  const next = { ...query }
  delete next.metric
  delete next.interval
  delete next.mode
  delete next.funnel
  delete next.dialog
  return next
}

export function buildQueryParams(
  query: AnalyticsQuery,
  extras: Record<string, unknown> = {}
) {
  const pieces: string[] = []
  const merged: Record<string, unknown> = { ...query, ...extras }

  if (merged.period) {
    pieces.push(`period=${encodeURIComponent(String(merged.period))}`)
  }
  if (merged.comparison) {
    pieces.push(`comparison=${encodeURIComponent(String(merged.comparison))}`)
  }
  if (merged.metric) {
    pieces.push(`metric=${encodeURIComponent(String(merged.metric))}`)
  }
  if (merged.interval) {
    pieces.push(`interval=${encodeURIComponent(String(merged.interval))}`)
  }
  if (merged.mode) {
    pieces.push(`mode=${encodeURIComponent(String(merged.mode))}`)
  }
  if (merged.funnel) {
    pieces.push(`funnel=${encodeURIComponent(String(merged.funnel))}`)
  }
  if (merged.withImported != null) {
    pieces.push(
      `with_imported=${encodeURIComponent(String(merged.withImported))}`
    )
  }
  if (merged.dialog) {
    pieces.push(`dialog=${encodeURIComponent(String(merged.dialog))}`)
  }
  if (merged.date)
    pieces.push(`date=${encodeURIComponent(String(merged.date))}`)
  if (merged.from)
    pieces.push(`from=${encodeURIComponent(String(merged.from))}`)
  if (merged.to) pieces.push(`to=${encodeURIComponent(String(merged.to))}`)
  if (merged.comparison) {
    if (merged.compareFrom) {
      pieces.push(
        `compare_from=${encodeURIComponent(String(merged.compareFrom))}`
      )
    }
    if (merged.compareTo) {
      pieces.push(`compare_to=${encodeURIComponent(String(merged.compareTo))}`)
    }
    if (merged.matchDayOfWeek != null) {
      pieces.push(
        `match_day_of_week=${encodeURIComponent(String(merged.matchDayOfWeek))}`
      )
    }
  }

  const filters = (merged.filters as AnalyticsQuery["filters"]) || {}
  for (const [key, value] of Object.entries(filters)) {
    if (value == null || value === "") continue
    pieces.push(serializeFilterEntry("is", key, String(value)))
  }

  const advanced =
    (merged.advancedFilters as AnalyticsQuery["advancedFilters"]) || []
  for (const entry of advanced) {
    if (!Array.isArray(entry) || entry.length < 3) continue
    const [operator, dimension, clause] = entry
    if (!operator || !dimension || clause == null) continue
    pieces.push(
      serializeFilterEntry(String(operator), String(dimension), String(clause))
    )
  }

  const labels = (merged.labels as AnalyticsQuery["labels"]) || {}
  const filtersObject = (merged.filters as AnalyticsQuery["filters"]) || {}
  for (const [key, value] of Object.entries(labels)) {
    if (!value) continue
    if (/^\d+$/.test(key)) continue
    const hasFilter = Object.prototype.hasOwnProperty.call(filtersObject, key)
    if (!hasFilter) continue
    if (String(filtersObject[key]) === String(value)) continue
    pieces.push(serializeLabelEntry(key, String(value)))
  }

  for (const [key, value] of Object.entries(extras)) {
    if (value == null) continue
    if (key === "order_by" && typeof value !== "string") {
      pieces.push(
        `${encodeURIComponent(key)}=${encodeURIComponent(JSON.stringify(value))}`
      )
    } else {
      pieces.push(
        `${encodeURIComponent(key)}=${encodeURIComponent(String(value))}`
      )
    }
  }

  const seen = new Set<string>()
  const deduped: string[] = []
  for (const piece of pieces) {
    if (seen.has(piece)) continue
    seen.add(piece)
    deduped.push(piece)
  }
  return deduped.join("&")
}

function parseBooleanParam(value: string | null): boolean | undefined {
  if (value == null) return undefined
  if (value === "true" || value === "1") return true
  if (value === "false" || value === "0") return false
  return undefined
}

export function parseQueryParams(
  search: string,
  fallback: AnalyticsQuery
): AnalyticsQuery {
  const params = new URLSearchParams(search)
  const filters: Record<string, string> = {}
  const labels: Record<string, string> = {}
  const advancedFilters: Array<[string, string, string]> = []

  for (const token of params.getAll("f")) {
    const parsed = parseTokenWithRemainder(token, ",", 3)
    if (!parsed) continue
    const [operator, key, value] = parsed
    if (!operator || !key || !value) continue
    if (operator === "is") {
      filters[key === "event:goal" ? "goal" : key] = value
    } else if (operator === "is_not" || operator === "contains") {
      advancedFilters.push([operator, key, value])
    }
  }

  for (const token of params.getAll("l")) {
    const parsed = parseTokenWithRemainder(token, ",", 2)
    if (!parsed) continue
    const [key, value] = parsed
    if (!key || !value) continue
    labels[key] = value
  }

  const next: AnalyticsQuery = {
    ...sanitizeReportQuery(fallback),
    filters,
    labels,
    advancedFilters,
  }

  const period = params.get("period")
  if (period) next.period = period as AnalyticsQuery["period"]

  const comparison = params.get("comparison")
  if (comparison) next.comparison = comparison as AnalyticsQuery["comparison"]
  else next.comparison = fallback.comparison ?? null

  const date = params.get("date")
  if (date) next.date = date
  else delete next.date

  const from = params.get("from")
  if (from) next.from = from
  else delete next.from

  const to = params.get("to")
  if (to) next.to = to
  else delete next.to

  const compareFrom = params.get("compare_from")
  if (compareFrom) next.compareFrom = compareFrom
  else delete next.compareFrom

  const compareTo = params.get("compare_to")
  if (compareTo) next.compareTo = compareTo
  else delete next.compareTo

  const withImported = parseBooleanParam(params.get("with_imported"))
  next.withImported = withImported ?? fallback.withImported

  const matchDayOfWeek = parseBooleanParam(params.get("match_day_of_week"))
  if (matchDayOfWeek != null) next.matchDayOfWeek = matchDayOfWeek
  else if (fallback.matchDayOfWeek != null) {
    next.matchDayOfWeek = fallback.matchDayOfWeek
  } else {
    delete next.matchDayOfWeek
  }

  return next
}

export function resolveInitialReportQuery(
  search: string | undefined,
  initialQuery: AnalyticsQuery,
  defaultQuery: AnalyticsQuery
): AnalyticsQuery {
  if (typeof search !== "string") {
    return sanitizeReportQuery(initialQuery)
  }

  return parseQueryParams(search, sanitizeReportQuery(defaultQuery))
}

export function mergeReportQueryParams(
  search: string,
  query: AnalyticsQuery
): URLSearchParams {
  const params = new URLSearchParams(search)
  for (const key of REPORT_QUERY_PARAM_KEYS) {
    params.delete(key)
  }
  params.delete("f")
  params.delete("l")

  const reportParams = new URLSearchParams(
    buildQueryParams(sanitizeReportQuery(query))
  )
  for (const [key, value] of reportParams.entries()) {
    params.append(key, value)
  }

  return canonicalizeDashboardSearchParams(params)
}
