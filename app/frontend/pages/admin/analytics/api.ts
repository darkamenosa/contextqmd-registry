import { canonicalizeDashboardSearchParams } from "./lib/dashboard-url-state"
import type {
  AnalyticsQuery,
  BehaviorsPayload,
  DevicesPayload,
  ListPayload,
  MainGraphPayload,
  MapPayload,
  SourceDebugPayload,
  TopStatsPayload,
} from "./types"

// --- URL param helpers (Plausible-style f/l scheme) ---
const NOT_URL_ENCODED_CHARACTERS = ":/"

function encodeURIComponentPermissive(
  input: string,
  permittedCharacters: string
): string {
  let result = encodeURIComponent(input)
  for (const ch of permittedCharacters) {
    const enc = encodeURIComponent(ch)
    if (enc !== ch) {
      // Replace all occurrences without using replaceAll (ES2021)
      result = result.split(enc).join(ch)
    }
  }
  return result
}

function serializeFilterEntry(operator: string, key: string, value: string) {
  // f=<operator>,<dimension>,<clause>
  const op = encodeURIComponentPermissive(operator, NOT_URL_ENCODED_CHARACTERS)
  const dim = encodeURIComponentPermissive(key, NOT_URL_ENCODED_CHARACTERS)
  const clause = encodeURIComponentPermissive(value, NOT_URL_ENCODED_CHARACTERS)
  return `f=${op},${dim},${clause}`
}

function serializeLabelEntry(key: string, label: string) {
  const k = encodeURIComponentPermissive(key, NOT_URL_ENCODED_CHARACTERS)
  const v = encodeURIComponentPermissive(label, NOT_URL_ENCODED_CHARACTERS)
  return `l=${k},${v}`
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

  if (merged.period)
    pieces.push(`period=${encodeURIComponent(String(merged.period))}`)
  if (merged.comparison)
    pieces.push(`comparison=${encodeURIComponent(String(merged.comparison))}`)
  if (merged.metric)
    pieces.push(`metric=${encodeURIComponent(String(merged.metric))}`)
  if (merged.interval)
    pieces.push(`interval=${encodeURIComponent(String(merged.interval))}`)
  if (merged.mode)
    pieces.push(`mode=${encodeURIComponent(String(merged.mode))}`)
  if (merged.funnel)
    pieces.push(`funnel=${encodeURIComponent(String(merged.funnel))}`)
  if (merged.withImported != null)
    pieces.push(
      `with_imported=${encodeURIComponent(String(merged.withImported))}`
    )
  if (merged.dialog)
    pieces.push(`dialog=${encodeURIComponent(String(merged.dialog))}`)
  if (merged.date)
    pieces.push(`date=${encodeURIComponent(String(merged.date))}`)
  if (merged.from)
    pieces.push(`from=${encodeURIComponent(String(merged.from))}`)
  if (merged.to) pieces.push(`to=${encodeURIComponent(String(merged.to))}`)
  if (merged.comparison) {
    if (merged.compareFrom)
      pieces.push(
        `compare_from=${encodeURIComponent(String(merged.compareFrom))}`
      )
    if (merged.compareTo)
      pieces.push(`compare_to=${encodeURIComponent(String(merged.compareTo))}`)
    if (merged.matchDayOfWeek != null)
      pieces.push(
        `match_day_of_week=${encodeURIComponent(String(merged.matchDayOfWeek))}`
      )
  }

  const filters = (merged.filters as AnalyticsQuery["filters"]) || {}
  for (const [key, value] of Object.entries(filters)) {
    if (value == null || value === "") continue
    pieces.push(serializeFilterEntry("is", key, String(value)))
  }

  // Advanced filters (is_not / contains) — append as repeated f entries
  const advanced =
    (merged.advancedFilters as AnalyticsQuery["advancedFilters"]) || []
  for (const entry of advanced) {
    if (!Array.isArray(entry) || entry.length < 3) continue
    const [op, dim, clause] = entry
    if (!op || !dim || clause == null) continue
    pieces.push(serializeFilterEntry(String(op), String(dim), String(clause)))
  }

  const labels = (merged.labels as AnalyticsQuery["labels"]) || {}
  const filtersObj = (merged.filters as AnalyticsQuery["filters"]) || {}
  for (const [k, v] of Object.entries(labels)) {
    if (!v) continue
    // Skip numeric label keys (e.g., city ID) — backend maps them to dimension labels.
    if (/^\d+$/.test(k)) continue
    // Only emit a label when there's a corresponding filter present.
    const hasFilter = Object.prototype.hasOwnProperty.call(filtersObj, k)
    if (!hasFilter) continue
    // Avoid duplicate when label equals the filter value (e.g., city "Mumbai").
    const filterVal = filtersObj[k]
    if (String(filterVal) === String(v)) continue
    pieces.push(serializeLabelEntry(k, String(v)))
  }

  // Extras (pagination/search/sort) remain standard encoding
  for (const [k, v] of Object.entries(extras)) {
    if (v == null) continue
    if (k === "order_by" && typeof v !== "string") {
      pieces.push(
        `${encodeURIComponent(k)}=${encodeURIComponent(JSON.stringify(v))}`
      )
    } else {
      pieces.push(`${encodeURIComponent(k)}=${encodeURIComponent(String(v))}`)
    }
  }

  // Final dedup (idempotent URL): remove any accidental duplicates while preserving order
  const seen = new Set<string>()
  const deduped: string[] = []
  for (const p of pieces) {
    if (seen.has(p)) continue
    seen.add(p)
    deduped.push(p)
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
  else if (fallback.matchDayOfWeek != null)
    next.matchDayOfWeek = fallback.matchDayOfWeek
  else delete next.matchDayOfWeek

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

type AnalyticsApiErrorBody = Record<string, unknown> | string | null | undefined

export class AnalyticsApiError extends Error {
  status: number
  body: AnalyticsApiErrorBody

  constructor(
    message: string,
    options: { status: number; body?: AnalyticsApiErrorBody }
  ) {
    super(message)
    this.name = "AnalyticsApiError"
    this.status = options.status
    this.body = options.body
  }
}

async function parseResponseBody(
  response: Response
): Promise<AnalyticsApiErrorBody> {
  const text = await response.text()
  if (!text) return null

  try {
    return JSON.parse(text) as AnalyticsApiErrorBody
  } catch {
    return text
  }
}

function analyticsErrorBody(error: unknown): Record<string, unknown> | null {
  if (!(error instanceof AnalyticsApiError)) return null
  if (!error.body || typeof error.body !== "object") return null
  return error.body as Record<string, unknown>
}

export function analyticsApiErrorCode(error: unknown): string | null {
  const body = analyticsErrorBody(error)
  const value = body?.errorCode
  return typeof value === "string" ? value : null
}

export function analyticsApiErrorMessage(error: unknown): string | null {
  if (error instanceof AnalyticsApiError) {
    if (typeof error.body === "string" && error.body.trim()) return error.body

    const body = analyticsErrorBody(error)
    const message = body?.message ?? body?.error
    if (typeof message === "string" && message.trim()) return message
  }

  if (error instanceof Error && error.message.trim()) return error.message
  return null
}

async function fetchJson<T>(
  path: string,
  query: AnalyticsQuery,
  extras: Record<string, unknown> = {},
  signal?: AbortSignal
) {
  const qs = buildQueryParams(query, extras)
  const response = await fetch(`${path}?${qs}`, {
    headers: { Accept: "application/json" },
    signal,
  })
  const body = await parseResponseBody(response)
  if (!response.ok) {
    throw new AnalyticsApiError(
      `Request failed with status ${response.status}`,
      {
        status: response.status,
        body,
      }
    )
  }
  return body as T
}

export function fetchTopStats(query: AnalyticsQuery, signal?: AbortSignal) {
  return fetchJson<TopStatsPayload>(
    "/admin/analytics/top_stats",
    query,
    {},
    signal
  )
}

export function fetchMainGraph(
  query: AnalyticsQuery,
  extras: { metric?: string; interval?: string } = {},
  signal?: AbortSignal
) {
  return fetchJson<MainGraphPayload>(
    "/admin/analytics/main_graph",
    query,
    extras,
    signal
  )
}

export function fetchSources(
  query: AnalyticsQuery,
  extras: { mode?: string } = {},
  signal?: AbortSignal
) {
  return fetchJson<ListPayload>(
    "/admin/analytics/sources",
    query,
    extras,
    signal
  )
}

export function fetchReferrers(
  query: AnalyticsQuery,
  extras: { source: string },
  signal?: AbortSignal
) {
  return fetchJson<ListPayload>(
    "/admin/analytics/referrers",
    query,
    extras,
    signal
  )
}

export function fetchSourceDebug(
  query: AnalyticsQuery,
  extras: { source: string },
  signal?: AbortSignal
) {
  return fetchJson<SourceDebugPayload>(
    "/admin/analytics/source_debug",
    query,
    extras,
    signal
  )
}

export function fetchSearchTerms(
  query: AnalyticsQuery,
  extras: Record<string, unknown> = {},
  signal?: AbortSignal
) {
  return fetchJson<ListPayload>(
    "/admin/analytics/search_terms",
    query,
    extras,
    signal
  )
}

export function fetchPages(
  query: AnalyticsQuery,
  extras: { mode?: string } = {},
  signal?: AbortSignal
) {
  return fetchJson<ListPayload>("/admin/analytics/pages", query, extras, signal)
}

export function fetchLocations(
  query: AnalyticsQuery,
  extras: { mode?: string } = {},
  signal?: AbortSignal
) {
  return fetchJson<MapPayload | ListPayload>(
    "/admin/analytics/locations",
    query,
    extras,
    signal
  )
}

export function fetchDevices(
  query: AnalyticsQuery,
  extras: { mode?: string } = {},
  signal?: AbortSignal
) {
  return fetchJson<DevicesPayload>(
    "/admin/analytics/devices",
    query,
    extras,
    signal
  )
}

export function fetchBehaviors(
  query: AnalyticsQuery,
  extras: { mode?: string; funnel?: string; property?: string } = {},
  signal?: AbortSignal
) {
  return fetchJson<BehaviorsPayload>(
    "/admin/analytics/behaviors",
    query,
    extras,
    signal
  )
}

export async function fetchBehaviorPropertyKeys(
  query: AnalyticsQuery,
  signal?: AbortSignal
) {
  const payload = await fetchJson<BehaviorsPayload>(
    "/admin/analytics/behaviors",
    query,
    {
      mode: "props",
      limit: "1",
      page: "1",
    },
    signal
  )

  return "list" in payload && Array.isArray(payload.propertyKeys)
    ? payload.propertyKeys
    : []
}

export async function fetchBehaviorPropertyValues(
  query: AnalyticsQuery,
  property: string,
  search = "",
  signal?: AbortSignal
) {
  const payload = await fetchJson<BehaviorsPayload>(
    "/admin/analytics/behaviors",
    query,
    {
      mode: "props",
      property,
      limit: "20",
      page: "1",
      search,
    },
    signal
  )

  if (!("list" in payload)) return []

  return payload.list.results.map((item) => ({
    label: String(item.name),
    value: String(item.name),
  }))
}

// Generic paginated list fetcher for Details modals
export async function fetchListPage(
  path: string,
  query: AnalyticsQuery,
  extras: Record<string, unknown> = {},
  opts: {
    limit?: number
    page?: number
    search?: string
    orderBy?: unknown[][]
  } = {},
  signal?: AbortSignal
) {
  const params: Record<string, unknown> = { ...extras }
  if (typeof opts.limit === "number") params.limit = String(opts.limit)
  if (typeof opts.page === "number") params.page = String(opts.page)
  if (typeof opts.search === "string") params.search = opts.search
  // Send order_by as JSON string following Plausible's pattern: [["metric", "direction"]]
  if (opts.orderBy && Array.isArray(opts.orderBy)) {
    params.order_by = JSON.stringify(opts.orderBy)
  }
  return fetchJson<ListPayload>(path, query, params, signal)
}
