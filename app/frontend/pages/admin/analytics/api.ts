import { analyticsScopedPath } from "./lib/path-prefix"
import {
  buildQueryParams,
  mergeReportQueryParams,
  parseQueryParams,
  resolveInitialReportQuery,
  sanitizeReportQuery,
} from "./lib/query-codec"
import type {
  AnalyticsQuery,
  BehaviorsPayload,
  DevicesPayload,
  ListPayload,
  MainGraphPayload,
  MapPayload,
  ProfileJourneyPayload,
  ProfileSessionPayload,
  ProfileSessionsListPayload,
  ProfilesPayload,
  SourceDebugPayload,
  TopStatsPayload,
} from "./types"

export {
  buildQueryParams,
  mergeReportQueryParams,
  parseQueryParams,
  resolveInitialReportQuery,
  sanitizeReportQuery,
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
    analyticsScopedPath("/top_stats"),
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
    analyticsScopedPath("/main_graph"),
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
    analyticsScopedPath("/sources"),
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
    analyticsScopedPath("/referrers"),
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
    analyticsScopedPath("/source_debug"),
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
    analyticsScopedPath("/search_terms"),
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
  return fetchJson<ListPayload>(
    analyticsScopedPath("/pages"),
    query,
    extras,
    signal
  )
}

export function fetchLocations(
  query: AnalyticsQuery,
  extras: { mode?: string } = {},
  signal?: AbortSignal
) {
  return fetchJson<MapPayload | ListPayload>(
    analyticsScopedPath("/locations"),
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
    analyticsScopedPath("/devices"),
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
    analyticsScopedPath("/behaviors"),
    query,
    extras,
    signal
  )
}

export function fetchProfiles(
  query: AnalyticsQuery,
  extras: { limit?: number; page?: number; search?: string } = {},
  signal?: AbortSignal
) {
  return fetchJson<ProfilesPayload>(
    analyticsScopedPath("/profiles"),
    query,
    extras,
    signal
  )
}

export function fetchProfileJourney(
  profileId: string,
  query: AnalyticsQuery,
  signal?: AbortSignal
) {
  return fetchJson<ProfileJourneyPayload>(
    analyticsScopedPath(`/profiles/${encodeURIComponent(profileId)}`),
    query,
    {},
    signal
  )
}

export async function fetchProfileSessions(
  profileId: string,
  extras: { limit?: number; page?: number; date?: string } = {},
  signal?: AbortSignal
) {
  const params = new URLSearchParams()
  if (extras.limit) params.set("limit", String(extras.limit))
  if (extras.page) params.set("page", String(extras.page))
  if (extras.date) params.set("date", extras.date)
  const url = `${analyticsScopedPath(`/profiles/${encodeURIComponent(profileId)}/sessions`)}?${params}`
  const response = await fetch(url, {
    headers: { Accept: "application/json" },
    signal,
  })
  if (!response.ok) throw new Error(`Request failed: ${response.status}`)
  return (await response.json()) as ProfileSessionsListPayload
}

export function fetchProfileSession(
  profileId: string,
  visitId: number,
  query: AnalyticsQuery,
  signal?: AbortSignal
) {
  return fetchJson<ProfileSessionPayload>(
    analyticsScopedPath(
      `/profiles/${encodeURIComponent(profileId)}/sessions/${visitId}`
    ),
    query,
    {},
    signal
  )
}

export async function fetchBehaviorPropertyKeys(
  query: AnalyticsQuery,
  signal?: AbortSignal
) {
  const payload = await fetchJson<BehaviorsPayload>(
    analyticsScopedPath("/behaviors"),
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
    analyticsScopedPath("/behaviors"),
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
